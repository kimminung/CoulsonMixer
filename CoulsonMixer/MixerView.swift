#if os(macOS)
import SwiftUI
import AppKit

struct MixerView: View {
    @State private var model = MixerModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("콜슨믹서")
                .font(.largeTitle.bold())
            Text("내부 오디오를 캡처해 Safari로 실시간 송출합니다.")
                .foregroundStyle(.secondary)

            Picker("캡처 대상", selection: $model.selectedSource) {
                Text("시스템 전체").tag(CaptureSource.systemWide)
                ForEach(model.availableApps) { app in
                    Text(app.name).tag(CaptureSource.process(pid: app.pid, name: app.name))
                }
            }
            .pickerStyle(.menu)
            .disabled(isRunning)

            HStack {
                Button(isRunning ? "송출 중지" : "송출 시작") {
                    isRunning ? model.stop() : model.start()
                }
                .buttonStyle(.borderedProminent)

                Button("앱 목록 새로고침") {
                    model.refreshAvailableApps()
                }
                .disabled(isRunning)
            }

            statusView

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 440, minHeight: 300)
        .onAppear { model.refreshAvailableApps() }
    }

    private var isRunning: Bool {
        if case .running = model.status { return true }
        return false
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.status {
        case .idle:
            Text("대기 중입니다.")
                .foregroundStyle(.secondary)
        case .running(let url):
            VStack(alignment: .leading, spacing: 8) {
                Label("송출 중: \(url.absoluteString)", systemImage: "dot.radiowaves.left.and.right")
                Text("연결된 Safari 클라이언트: \(model.clientCount)")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("URL 복사") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                    Button("Safari에서 열기") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    MixerView()
}
#endif
