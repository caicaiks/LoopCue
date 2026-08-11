import SwiftUI

/// 强提醒卡片（PRD 6.4 / 技术方案 11.4）。
///
/// M0 最小实现：说明文案 + 完成按钮。完成走 Engine 统一回执，
/// 不做完成/跳过之外的操作；无障碍与多提醒队列在 M1 补齐。
struct StrongReminderView: View {
    let reminderID: UUID
    let cycleID: UUID
    let onComplete: (UUID, UUID) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
            Text("该行动已等待回应")
                .font(.title2)
                .bold()
            Text("如果已经完成，请点击下方按钮结束本轮提醒。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("已完成") {
                onComplete(reminderID, cycleID)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.88))
        .foregroundStyle(.white)
    }
}

