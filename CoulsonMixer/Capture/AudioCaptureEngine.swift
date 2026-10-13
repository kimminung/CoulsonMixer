import Foundation
import CoreAudio
import AVFAudio

#if os(macOS)

enum AudioCaptureError: LocalizedError {
    case processNotFound
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case startFailed(OSStatus)
    case missingStreamFormat

    var errorDescription: String? {
        switch self {
        case .processNotFound:
            return "선택한 앱의 오디오 프로세스를 찾을 수 없습니다."
        case .tapCreationFailed(let status):
            return "오디오 탭 생성에 실패했습니다 (OSStatus \(status)). 시스템 설정 > 개인정보 보호 및 보안에서 시스템 오디오 녹음 권한을 확인하세요."
        case .aggregateDeviceCreationFailed(let status):
            return "애그리게이트 장치 생성에 실패했습니다 (OSStatus \(status))."
        case .ioProcCreationFailed(let status):
            return "오디오 IO 등록에 실패했습니다 (OSStatus \(status))."
        case .startFailed(let status):
            return "오디오 캡처 시작에 실패했습니다 (OSStatus \(status))."
        case .missingStreamFormat:
            return "오디오 스트림 포맷을 읽을 수 없습니다."
        }
    }
}

enum CaptureSource: Hashable {
    case systemWide
    case process(pid: pid_t, name: String)
}

/// Captures internal audio via a Core Audio process tap (macOS 14.4+), without installing a
/// virtual audio driver. Runs its IO callback on CoreAudio's realtime thread, so this type opts
/// out of the module's default MainActor isolation.
nonisolated final class AudioCaptureEngine {
    private(set) var isRunning = false
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    func start(source: CaptureSource) throws {
        stop()

        let ownProcessObjectID = try Self.processObjectID(for: getpid())

        let description: CATapDescription
        switch source {
        case .systemWide:
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcessObjectID])
        case .process(let pid, _):
            let processObjectID = try Self.processObjectID(for: pid)
            description = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        }
        description.isPrivate = true

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else { throw AudioCaptureError.tapCreationFailed(status) }

        let tapUID: String
        do {
            tapUID = try Self.tapUID(forTap: newTapID)
        } catch {
            AudioHardwareDestroyProcessTap(newTapID)
            throw error
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "ColsonMixer Tap Aggregate",
            kAudioAggregateDeviceUIDKey as String: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: tapUID,
                    kAudioSubTapDriftCompensationKey as String: true
                ]
            ]
        ]

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard status == noErr else {
            AudioHardwareDestroyProcessTap(newTapID)
            throw AudioCaptureError.aggregateDeviceCreationFailed(status)
        }

        guard let format = try? Self.streamFormat(forDevice: newAggregateID) else {
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw AudioCaptureError.missingStreamFormat
        }

        var newIOProcID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&newIOProcID, newAggregateID, nil) { [weak self] _, inInputData, _, _, _ in
            guard let self, let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil) else { return }
            self.onBuffer?(buffer)
        }
        guard status == noErr, let resolvedIOProcID = newIOProcID else {
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw AudioCaptureError.ioProcCreationFailed(status)
        }

        status = AudioDeviceStart(newAggregateID, resolvedIOProcID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(newAggregateID, resolvedIOProcID)
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw AudioCaptureError.startFailed(status)
        }

        tapID = newTapID
        aggregateDeviceID = newAggregateID
        ioProcID = resolvedIOProcID
        isRunning = true
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        isRunning = false
    }

    private static func processObjectID(for pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pidCopy = pid
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pidCopy,
            &dataSize,
            &objectID
        )
        guard status == noErr, objectID != AudioObjectID(kAudioObjectUnknown) else {
            throw AudioCaptureError.processNotFound
        }
        return objectID
    }

    private static func tapUID(forTap tapID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer -> OSStatus in
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr else { throw AudioCaptureError.tapCreationFailed(status) }
        return uid as String
    }

    private static func streamFormat(forDevice deviceID: AudioObjectID) throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            throw AudioCaptureError.missingStreamFormat
        }
        return format
    }
}

#endif
