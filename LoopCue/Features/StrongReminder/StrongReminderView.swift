import SwiftUI

/// 强提醒卡片（PRD 6.4 / 技术方案 11.4）。
///
/// 数据驱动：展示 Engine 快照中的主卡片（行动名、提醒文案、自定义完成
/// 按钮、已等待时长），提供延后 / 跳过本次 / 暂时关闭。所有操作只发
/// Intent 给 Engine，不做本地状态推导。
///
/// 无障碍：使用系统控件与纯文本，支持 VoiceOver 朗读；「暂时关闭」绑定
/// Escape（.cancelAction）。视觉上避免红色警告与动画，兼容 Reduce Motion；
/// 高对比度由系统默认配色保证，不依赖单一颜色传达状态。
struct StrongReminderView: View {
    /// 当前主卡片（strongQueue 的第一项）。
    let item: StrongReminderSnapshot
    /// 队列总数（含当前项），>1 时显示「还有 N 项等待回应」。
    let queueCount: Int
    let onComplete: (UUID, UUID) -> Void
    let onSkip: (UUID, UUID) -> Void
    let onSnooze: (UUID, UUID) -> Void
    let onDismiss: (UUID, UUID) -> Void

    private var canSnooze: Bool { item.snoozeCount < item.maxSnoozeCount }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: item.icon.rawValue)
                .font(.system(size: 56))
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(item.name)
                    .font(.title)
                    .bold()
                if !item.message.isEmpty {
                    Text(item.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(Self.waitingText(item.strongTriggeredAt, now: context.date))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Self.waitingText(item.strongTriggeredAt, now: context.date))
            }

            if queueCount > 1 {
                Text("还有 \(queueCount - 1) 项等待回应")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("还有 \(queueCount - 1) 项等待回应")
            }

            Button(item.completionLabel) {
                onComplete(item.reminderID, item.cycleID)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("结束本轮提醒，开始新一轮")

            HStack(spacing: 12) {
                if canSnooze {
                    Button("\(Self.snoozeLabel(item.snoozeDuration)) 后提醒") {
                        onSnooze(item.reminderID, item.cycleID)
                    }
                    .accessibilityHint("延后本轮提醒，不修改原始周期")
                }
                Button("跳过本次") {
                    onSkip(item.reminderID, item.cycleID)
                }
                Button("暂时关闭") {
                    onDismiss(item.reminderID, item.cycleID)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("暂时隐藏全屏提醒，5 分钟后再次出现")
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.88))
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
    }

    /// 「这项行动已经等待 X 分钟」（PRD 10.3）。
    private static func waitingText(_ triggeredAt: Date?, now: Date) -> String {
        guard let triggeredAt else { return "这项行动正在等待你的回应" }
        let minutes = max(0, Int(now.timeIntervalSince(triggeredAt) / 60))
        return "这项行动已经等待 \(minutes) 分钟"
    }

    /// 延后按钮文案：配置的延后时长（至少 1 分钟）。
    private static func snoozeLabel(_ duration: Duration) -> String {
        let minutes = max(1, Int(duration.components.seconds) / 60)
        return "\(minutes) 分钟"
    }
}
