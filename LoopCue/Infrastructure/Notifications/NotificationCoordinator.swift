import Foundation
import UserNotifications

/// 通知 Category 与动作标识（PRD F-04 / 技术方案 10.2）。
enum NotificationActionID {
    static let category = "REMINDER_RESPONSE"
    static let complete = "COMPLETE"
    static let snooze = "SNOOZE"
}

enum NotificationUserInfoKey {
    static let reminderID = "reminderID"
    static let cycleID = "cycleID"
}

/// 注册带「已完成 / 稍后提醒」操作按钮的通知 Category。
func registerNotificationCategories() {
    let complete = UNNotificationAction(
        identifier: NotificationActionID.complete,
        title: "已完成",
        options: []
    )
    let snooze = UNNotificationAction(
        identifier: NotificationActionID.snooze,
        title: "稍后提醒",
        options: []
    )
    let category = UNNotificationCategory(
        identifier: NotificationActionID.category,
        actions: [complete, snooze],
        intentIdentifiers: [],
        options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([category])
}

/// 处理通知回调：前台展示 + 动作按钮回执（技术方案 10.4）。
final class NotificationResponseHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let engine: ReminderEngine

    init(engine: ReminderEngine) {
        self.engine = engine
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 应用在前台也展示横幅与声音，不吞掉弱提醒。
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard
            let reminderIDString = userInfo[NotificationUserInfoKey.reminderID] as? String,
            let cycleIDString = userInfo[NotificationUserInfoKey.cycleID] as? String,
            let reminderID = UUID(uuidString: reminderIDString),
            let cycleID = UUID(uuidString: cycleIDString)
        else {
            completionHandler()
            return
        }

        // 先同步回调完成通知处理，引擎写入放到独立 Task，避免把 sending 闭包传入 Task。
        completionHandler()
        let actionIdentifier = response.actionIdentifier
        Task {
            switch actionIdentifier {
            case NotificationActionID.complete:
                try? await engine.handle(
                    .complete(reminderID: reminderID, cycleID: cycleID),
                    now: Date()
                )
            case NotificationActionID.snooze:
                try? await engine.handle(
                    .snooze(reminderID: reminderID, cycleID: cycleID),
                    now: Date()
                )
            default:
                // 点击通知正文：打开主窗口（M1 实现）。
                break
            }
        }
    }
}

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
        content.categoryIdentifier = NotificationActionID.category
        content.userInfo = [
            NotificationUserInfoKey.reminderID: reminderID.uuidString,
            NotificationUserInfoKey.cycleID: cycleID.uuidString,
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
