import SwiftUI

struct ContentView: View {
    var body: some View {
        #if os(macOS)
        MixerView()
        #else
        ContentUnavailableView(
            "macOS 전용 기능입니다",
            systemImage: "desktopcomputer",
            description: Text("콜슨믹서는 macOS에서 내부 오디오를 캡처해 Safari로 송출합니다.")
        )
        #endif
    }
}

#Preview {
    ContentView()
}
