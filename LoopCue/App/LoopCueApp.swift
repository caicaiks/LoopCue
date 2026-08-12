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

        Window("提醒列表", id: "reminderList") {
            ReminderListView(appDelegate: appDelegate)
        }

        Window("设置", id: "settings") {
            SettingsView(
                appDelegate: appDelegate,
                settings: appDelegate.settings
            )
        }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let appModel = appDelegate.appModel {
                MenuBarView(
                    appModel: appModel,
                    onSend: { appDelegate.send($0) },
                    onOpenList: {
                        // 菜单栏（accessory）应用需先激活自身，普通窗口才能带到最前
                        //（技术方案 12；与 OverlayPresenter 一致）。
                        NSApp.activate(ignoringOtherApps: true)
                        DispatchQueue.main.async {
                            openWindow(id: "reminderList")
                        }
                    },
                    onOpenSettings: {
                        // 与提醒列表一致：accessory 应用需先激活自身。
                        NSApp.activate(ignoringOtherApps: true)
                        DispatchQueue.main.async {
                            openWindow(id: "settings")
                        }
                    },
                    isLoginItemEnabled: appDelegate.isLoginItemEnabled,
                    loginItemNeedsApproval: appDelegate.loginItemNeedsApproval,
                    onToggleLoginItem: { appDelegate.setLoginItemEnabled($0) }
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
