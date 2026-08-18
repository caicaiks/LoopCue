import AppKit
import SwiftUI

/// 菜单栏主界面：下一项投影、等待回应快捷操作（PRD 6.5 / 技术方案 14.2）。
struct MenuBarView: View {
    @ObservedObject var appModel: AppModel
    let onSend: (ReminderIntent) -> Void
    let onOpenList: () -> Void
    let onOpenSettings: () -> Void
    let isLoginItemEnabled: Bool
    let loginItemNeedsApproval: Bool
    let onToggleLoginItem: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("叮刻 LoopCue")
                .font(.headline)
                .padding(.bottom, 2)

            if let snapshot = appModel.snapshot {
                if snapshot.reminders.isEmpty {
                    Text("暂无提醒")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    if let next = snapshot.nextReminder {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("下一个提醒")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Image(systemName: next.icon.rawValue)
                                Text(next.name)
                                Spacer(minLength: 12)
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text(UIFormatters.countdown(
                                        next.remainingToWeak,
                                        since: snapshot.now,
                                        now: context.date
                                    ))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .font(.callout)
                            Button("立即提醒一次") {
                                onSend(.triggerWeakNow(
                                    reminderID: next.reminderID,
                                    cycleID: next.cycleID
                                ))
                            }
                        }
                        divider
                    }

                    if !snapshot.pendingResponses.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("等待回应")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(snapshot.pendingResponses, id: \.cycleID) { pending in
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    pendingRow(pending, since: snapshot.now, now: context.date)
                                }
                            }
                        }
                        divider
                    }

                    ForEach(snapshot.reminders) { reminder in
                        HStack(spacing: 8) {
                            Image(systemName: reminder.config.icon.rawValue)
                            Text(reminder.config.name)
                            Spacer(minLength: 12)
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
                    .padding(.vertical, 4)
            }

            if let allowed = appModel.notificationAllowed, !allowed {
                warningRow(
                    icon: "bell.slash",
                    text: "通知未开启（\(appModel.notificationStatusDetail ?? "未知")）。请在 系统设置 → 通知 → LoopCue 中开启。",
                    isFailure: true
                )
            }

            if let result = appModel.notificationSubmitResult {
                warningRow(
                    icon: result.isFailure ? "exclamationmark.triangle" : "checkmark.circle",
                    text: result.detail,
                    isFailure: result.isFailure
                )
            }

            if let snapshot = appModel.snapshot, snapshot.isGloballyPaused {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                    Text("已全局暂停")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("恢复") {
                        onSend(.resumeAll)
                    }
                }
                .font(.callout)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("暂停")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("30 分钟") { onSend(.pauseAll(.timed(.minutes(30)))) }
                    Button("1 小时") { onSend(.pauseAll(.timed(.hours(1)))) }
                    Button("到明天") { onSend(.pauseAll(.untilMidnight)) }
                }
                .font(.caption)
            }

            divider

            Toggle("登录时启动", isOn: Binding(
                get: { isLoginItemEnabled },
                set: { onToggleLoginItem($0) }
            ))
            .font(.callout)

            if loginItemNeedsApproval {
                Text("请在 系统设置 → 通用 → 登录项 中确认后生效。")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("打开提醒列表") {
                    onOpenList()
                }
                Button("设置") {
                    onOpenSettings()
                }
                Spacer(minLength: 12)
                Button("退出 LoopCue") {
                    NSApp.terminate(nil)
                }
            }
            .font(.callout)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .frame(minWidth: 320)
    }

    private var divider: some View {
        Divider()
            .padding(.vertical, 2)
    }

    private func warningRow(icon: String, text: String, isFailure: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(isFailure ? Color.orange : Color.secondary)
    }

    private func pendingRow(
        _ pending: PendingReminderSnapshot,
        since snapshotNow: Date,
        now: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: pending.icon.rawValue)
                Text(pending.name)
                Spacer(minLength: 12)
                Text(pendingLabel(pending, since: snapshotNow, now: now))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            HStack(spacing: 10) {
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
    }

    private func pendingLabel(
        _ pending: PendingReminderSnapshot,
        since snapshotNow: Date,
        now: Date
    ) -> String {
        switch pending.phase {
        case .weakPending:
            if let remaining = pending.remainingToStrong {
                return "等待回应 · \(UIFormatters.countdown(remaining, since: snapshotNow, now: now)) 后升级"
            }
            return "等待回应"
        case .snoozed:
            if let remaining = pending.remainingToStrong {
                return "已延后 · \(UIFormatters.countdown(remaining, since: snapshotNow, now: now)) 后提醒"
            }
            return "已延后"
        case .strongPending:
            if let remaining = pending.remainingToStrong, remaining > .zero {
                return "已暂时关闭 · \(UIFormatters.countdown(remaining, since: snapshotNow, now: now)) 后再次提醒"
            }
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
