import Foundation
import UserNotifications

/// 执行 ReminderEffect 的抽象。真实实现走 UNUserNotificationCenter；
/// 测试使用 Mock 记录调用。
protocol EffectExecutor: Sendable {
    func execute(_ effect: ReminderEffect) async
}

/// 系统效果执行器：弱提醒通知 + 清理。
///
/// 全屏强提醒（Overlay）属于 M0-A 真机验证项，暂以 no-op 占位。
struct SystemEffectExecutor: EffectExecutor {
    func execute(_ effect: ReminderEffect) async {
        switch effect {
        case .sendWeakNotification(let reminderID, let cycleID):
            await sendWeakNotification(reminderID: reminderID, cycleID: cycleID)
        case .clearNotifications(let reminderID, let cycleID):
            await clear(reminderID: reminderID, cycleID: cycleID)
        case .presentStrongOverlay:
            // TODO(M0-A): 接入 OverlayPresenter 多屏全屏窗口
            break
        case .dismissStrongOverlay:
            // TODO(M0-A): 关闭对应 cycleID 的覆盖窗口
            break
        }
    }

    private func sendWeakNotification(reminderID: UUID, cycleID: UUID) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "叮刻 LoopCue"
        content.body = "该行动需要你的回应"
        content.userInfo = [
            "reminderID": reminderID.uuidString,
            "cycleID": cycleID.uuidString,
        ]
        let identifier = "weak.\(reminderID.uuidString).\(cycleID.uuidString)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private func clear(reminderID: UUID, cycleID: UUID) async {
        let center = UNUserNotificationCenter.current()
        let prefix = "weak.\(reminderID.uuidString).\(cycleID.uuidString)"
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = pending
            .filter { $0.identifier.hasPrefix(prefix) }
            .map(\.identifier)
        if !pendingIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        }
        center.removeDeliveredNotifications(withIdentifiers: [prefix])
    }
}

