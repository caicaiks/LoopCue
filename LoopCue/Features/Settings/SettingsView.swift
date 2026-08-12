import AppKit
import SwiftUI

/// 设置页（PRD 9.2 / 10.4 / 技术方案 14.2）。
///
/// 包含通知权限状态与系统设置修复入口、新建提醒默认值、
/// 登录启动、数据清理。所有写操作仍经由 AppDelegate → Engine / LoginItem，
/// 页面不直接触碰业务状态。
struct SettingsView: View {
    @ObservedObject var appDelegate: AppDelegate
    @ObservedObject var settings: AppSettingsStore

    @State private var confirmDeleteAll = false

    private var snapshot: AppSnapshot? { appDelegate.appModel?.snapshot }

    var body: some View {
        Form {
            Section("通知") {
                notificationRow
            }

            Section("新建提醒默认值") {
                Picker("默认覆盖显示器", selection: $settings.defaultDisplayScope) {
                    Text("所有显示器").tag(DisplayScope.all)
                    Text("仅当前显示器").tag(DisplayScope.current)
                }
                Picker("默认离开阈值", selection: $settings.defaultAwayMinutes) {
                    ForEach(AppSettingsStore.awayOptions, id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
                Text("新建提醒时使用这些默认值；已有提醒不受影响。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("登录") {
                Toggle("登录时启动", isOn: Binding(
                    get: { appDelegate.isLoginItemEnabled },
                    set: { appDelegate.setLoginItemEnabled($0) }
                ))
                if appDelegate.loginItemNeedsApproval {
                    Text("请在 系统设置 → 通用 → 登录项 中确认后生效。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("数据") {
                #if DEBUG
                Button("清空数据并重新开始", role: .destructive) {
                    appDelegate.resetForTesting()
                }
                #endif
                Button("删除所有本地数据", role: .destructive) {
                    confirmDeleteAll = true
                }
                Text("删除后无法恢复；提醒配置、记录与通知将全部移除。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .frame(minWidth: 420, minHeight: 440)
        .onAppear {
            appDelegate.refreshNotificationStatus()
        }
        .confirmationDialog(
            "删除所有本地数据？",
            isPresented: $confirmDeleteAll,
            titleVisibility: .visible
        ) {
            Button("删除所有数据", role: .destructive) {
                appDelegate.deleteAllLocalData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有提醒配置与本地记录将被永久删除。删除后应用回到全新状态。")
        }
    }

    @ViewBuilder
    private var notificationRow: some View {
        let allowed = appDelegate.appModel?.notificationAllowed
        HStack(spacing: 8) {
            Image(systemName: allowed == true ? "bell.fill" : "bell.slash")
                .foregroundStyle(allowed == true ? Color.accentColor : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(allowed == true ? "通知已开启" : "系统通知已关闭")
                if let detail = appDelegate.appModel?.notificationStatusDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if allowed == true {
                Button("重新检查") {
                    appDelegate.refreshNotificationStatus()
                }
            }
        }

        if allowed != true {
            Button("打开系统设置") {
                NotificationPermissionLink.openSystemSettings()
            }
            Text("叮刻仍在计时，但无法发送弱提醒。你可以前往系统设置重新开启。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 打开系统通知设置（技术方案 10.1：不依赖私有 API，失败回退系统设置首页）。
enum NotificationPermissionLink {
    static func openSystemSettings() {
        let workspace = NSWorkspace.shared
        let notificationURL = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        )
        let opened = notificationURL.map { workspace.open($0) } ?? false
        if !opened {
            // 目标系统不支持深链时打开系统设置首页，由用户手动进入通知。
            _ = workspace.open(URL(string: "x-apple.systempreferences:")!)
        }
    }
}
