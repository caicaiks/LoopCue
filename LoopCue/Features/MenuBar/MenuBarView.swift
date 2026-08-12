import AppKit
import SwiftUI

/// 菜单栏主界面：下一项投影、等待回应快捷操作（PRD 6.5 / 技术方案 14.2）。
struct MenuBarView: View {
    @ObservedObject var appModel: AppModel
    let onSend: (ReminderIntent) -> Void
    let onOpenList: () -> Void
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
                    if let next = snapshot.nextReminder {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("下一个提醒")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Image(systemName: next.icon.rawValue)
                                Text(next.name)
                                Spacer()
                                Text(UIFormatters.remaining(next.remainingToWeak))
                            }
                            .font(.callout)
                        }
                        Divider()
                    }

                    if !snapshot.pendingResponses.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("等待回应")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(snapshot.pendingResponses, id: \.cycleID) { pending in
                                pendingRow(pending)
                            }
                        }
                        Divider()
                    }

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

            if let snapshot = appModel.snapshot, snapshot.isGloballyPaused {
                HStack {
                    Image(systemName: "pause.circle.fill")
                    Text("已全局暂停")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("恢复") {
                        onSend(.resumeAll)
                    }
                }
                .font(.callout)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("暂停")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("30 分钟") { onSend(.pauseAll(.timed(.minutes(30)))) }
                    Button("1 小时") { onSend(.pauseAll(.timed(.hours(1)))) }
                    Button("到明天") { onSend(.pauseAll(.untilMidnight)) }
                }
                .font(.caption)
            }

            Divider()

            Button("打开提醒列表") {
                onOpenList()
            }
            .font(.callout)

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
        .frame(minWidth: 300)
    }

    private func pendingRow(_ pending: PendingReminderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: pending.icon.rawValue)
                Text(pending.name)
                Spacer()
                Text(pendingLabel(pending))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("已完成") {
                    onSend(.complete(reminderID: pending.reminderID, cycleID: pending.cycleID))
                }
                if pending.phase == .weakPending || pending.phase == .strongPending,
                   pending.snoozeCount < pending.maxSnoozeCount {
                    Button("稍后提醒") {
                        onSend(.snooze(reminderID: pending.reminderID, cycleID: pending.cycleID))
                    }
                }
                Button("跳过") {
                    onSend(.skip(reminderID: pending.reminderID, cycleID: pending.cycleID))
                }
            }
            .font(.caption)
        }
        .font(.callout)
    }

    private func pendingLabel(_ pending: PendingReminderSnapshot) -> String {
        switch pending.phase {
        case .weakPending:
            if let remaining = pending.remainingToStrong {
                return "等待回应 · \(UIFormatters.remaining(remaining)) 后升级"
            }
            return "等待回应"
        case .snoozed:
            if let remaining = pending.remainingToStrong {
                return "已延后 · \(UIFormatters.remaining(remaining)) 后提醒"
            }
            return "已延后"
        case .strongPending:
            return "等待升级"
        case .counting:
            return "计时中"
        }
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
