import Foundation

#if os(macOS)

struct CapturableApp: Identifiable, Hashable {
    let pid: pid_t
    let name: String

    var id: pid_t { pid }
}

#endif
