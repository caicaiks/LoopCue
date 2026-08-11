import AppKit
import SwiftUI

/// 菜单栏主界面：展示 Engine 快照中的提醒与阶段（技术方案 14.2）。
struct MenuBarView: View {
    @ObservedObject var appModel: AppModel
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("叮刻 LoopCue")
                .font(.headline)

            if let snapshot = appModel.snapshot {
                if snapshot.reminders.isEmpty {
                    Text("暂无提醒")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.reminders) { reminder in
                        HStack {
                            Image(systemName: reminder.config.icon.rawValue)
                            Text(reminder.config.name)
                            Spacer()
                            Text(phaseLabel(reminder.phase))
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            } else {
                Text("加载中…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let allowed = appModel.notificationAllowed, !allowed {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "bell.slash")
                    Text("通知未开启（\(appModel.notificationStatusDetail ?? "未知")）。请在 系统设置 → 通知 → LoopCue 中开启。")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Divider()

            Button("清空数据并重新开始") {
                onReset()
            }
            .font(.callout)

            Button("退出 LoopCue") {
                NSApp.terminate(nil)
            }
            .font(.callout)
        }
        .padding()
        .frame(minWidth: 260)
    }

    private func phaseLabel(_ phase: CyclePhase?) -> String {
        switch phase {
        case .counting: return "计时中"
        case .weakPending: return "等待回应"
        case .snoozed: return "已延后"
        case .strongPending: return "等待升级"
        case nil: return "—"
        }
    }
}
