import Foundation
import AVFAudio

#if os(macOS)

/// Wires capture → encode → broadcast entirely off the main actor. The capture callback fires
/// on CoreAudio's realtime thread, so none of this hot path may hop to MainActor; only
/// infrequent events (client count changes) cross back via `onClientCountChanged`.
nonisolated final class AudioPipeline {
    private let captureEngine = AudioCaptureEngine()
    private let broadcastServer = BroadcastServer()
    private let encoderLock = NSLock()
    private var encoder: AudioEncoder?

    var onClientCountChanged: (@Sendable (Int) -> Void)? {
        get { broadcastServer.onClientCountChanged }
        set { broadcastServer.onClientCountChanged = newValue }
    }

    func start(source: CaptureSource) throws -> UInt16 {
        try broadcastServer.start()

        encoderLock.lock()
        encoder = nil
        encoderLock.unlock()

        captureEngine.onBuffer = { [weak self] buffer in
            guard let self else { return }
            self.encoderLock.lock()
            if self.encoder == nil {
                self.encoder = AudioEncoder(inputFormat: buffer.format)
            }
            let packets = self.encoder?.encode(buffer) ?? []
            self.encoderLock.unlock()
            for packet in packets {
                self.broadcastServer.broadcast(packet)
            }
        }

        do {
            try captureEngine.start(source: source)
        } catch {
            broadcastServer.stop()
            throw error
        }

        return broadcastServer.port
    }

    func stop() {
        captureEngine.stop()
        broadcastServer.stop()
        encoderLock.lock()
        encoder = nil
        encoderLock.unlock()
    }
}

#endif
