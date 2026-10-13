import Foundation
import Observation

#if os(macOS)
import AppKit

@Observable
final class MixerModel {
    enum Status: Equatable {
        case idle
        case running(url: URL)
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var clientCount: Int = 0
    var availableApps: [CapturableApp] = []
    var selectedSource: CaptureSource = .systemWide

    private let pipeline = AudioPipeline()

    init() {
        refreshAvailableApps()
        pipeline.onClientCountChanged = { [weak self] count in
            Task { @MainActor in
                self?.clientCount = count
            }
        }
    }

    func refreshAvailableApps() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        availableApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != currentPID }
            .map { CapturableApp(pid: $0.processIdentifier, name: $0.localizedName ?? "알 수 없는 앱") }
            .sorted { $0.name < $1.name }
    }

    func start() {
        do {
            let port = try pipeline.start(source: selectedSource)
            guard let url = URL(string: "http://127.0.0.1:\(port)/") else {
                throw BroadcastServerError.noPortAvailable
            }
            status = .running(url: url)
        } catch {
            pipeline.stop()
            status = .error(error.localizedDescription)
        }
    }

    func stop() {
        pipeline.stop()
        clientCount = 0
        status = .idle
    }
}

#endif
