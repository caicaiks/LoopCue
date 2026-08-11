import SwiftUI

@main
struct LoopCueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("叮刻 LoopCue", systemImage: "timer") {
            MenuBarContent()
                .environmentObject(appDelegate)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var appDelegate: AppDelegate

    var body: some View {
        Group {
            if let appModel = appDelegate.appModel {
                MenuBarView(
                    appModel: appModel,
                    onReset: { appDelegate.resetForTesting() }
                )
            } else if let error = appDelegate.launchError {
                VStack(alignment: .leading, spacing: 4) {
                    Text("初始化失败")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding()
                .frame(minWidth: 260)
            } else {
                Text("初始化中…")
                    .padding()
                    .frame(minWidth: 260)
            }
        }
        .onAppear {
            appDelegate.refreshNotificationStatus()
        }
    }
}
