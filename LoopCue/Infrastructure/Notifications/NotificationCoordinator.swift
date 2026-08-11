import Foundation
import UserNotifications

/// 执行 ReminderEffect 的抽象。真实实现走 UNUserNotificationCenter；
/// 测试使用 Mock 记录调用。
protocol EffectExecutor: Sendable {
    func execute(_ effect: ReminderEffect) async
}

/// 系统效果执行器：弱提醒通知 + 清理。
struct SystemEffectExecutor: EffectExecutor {
    private let overlay: any OverlayPresenting

    init(overlay: any OverlayPresenting) {
        self.overlay = overlay
    }

    func execute(_ effect: ReminderEffect) async {
        switch effect {
        case .sendWeakNotification(let reminderID, let cycleID):
            await sendWeakNotification(reminderID: reminderID, cycleID: cycleID)
        case .clearNotifications(let reminderID, let cycleID):
            await clear(reminderID: reminderID, cycleID: cycleID)
        case .presentStrongOverlay(let reminderID, let cycleID):
            await overlay.present(reminderID: reminderID, cycleID: cycleID)
        case .dismissStrongOverlay(let reminderID, let cycleID):
            await overlay.dismiss(reminderID: reminderID, cycleID: cycleID)
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
