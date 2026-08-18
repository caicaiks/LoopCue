import Foundation
import os
import UserNotifications

/// 通知操作标识（固定 ID，展示标题由 Category 动态决定，技术方案 10.2）。
enum NotificationActionID {
    static let complete = "COMPLETE_ACTION"
    static let snooze = "SNOOZE_ACTION"
}

/// 通知 userInfo 键。
enum NotificationUserInfoKey {
    static let reminderID = "reminderID"
    static let cycleID = "cycleID"
    static let effectID = "effectID"
    static let schemaVersion = "schemaVersion"
}

/// 通知 userInfo 的 schema 版本。
enum NotificationSchemaVersion {
    static let current = 1
}

/// 删除全部本地数据时移除所有已排期与已送达的通知（PRD 16.2）。
enum NotificationCleanup {
    static func removeAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}

/// 动态 Category ID：按「完成文案 + 延后分钟数」生成稳定标识
/// （技术方案 10.2）。同一提醒的配置变化会生成新 ID，不影响旧通知。
enum NotificationCategoryID {
    static func make(completionLabel: String, snoozeMinutes: Int64) -> String {
        "loopcue.response.\(completionLabel).\(snoozeMinutes)"
    }
}

/// 由配置集合生成通知 Category 集合（纯函数，便于测试）。
/// - 完成按钮标题 = completionLabel；
/// - 延后按钮标题 = 「N 分钟后提醒」；
/// - 相同 (completionLabel, snoozeMinutes) 的提醒共享一个 Category。
func makeNotificationCategories(for configs: [ReminderConfig]) -> Set<UNNotificationCategory> {
    var categories: [String: UNNotificationCategory] = [:]
    for config in configs {
        let snoozeMinutes = config.snoozeDuration.components.seconds / 60
        let categoryID = NotificationCategoryID.make(
            completionLabel: config.completionLabel,
            snoozeMinutes: snoozeMinutes
        )
        guard categories[categoryID] == nil else { continue }
        let complete = UNNotificationAction(
            identifier: NotificationActionID.complete,
            title: config.completionLabel,
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: NotificationActionID.snooze,
            title: "\(snoozeMinutes) 分钟后提醒",
            options: []
        )
        categories[categoryID] = UNNotificationCategory(
            identifier: categoryID,
            actions: [complete, snooze],
            intentIdentifiers: [],
            options: []
        )
    }
    return Set(categories.values)
}

/// 注册当前提醒集合对应的全部通知 Category。
/// 启动、配置增删改后由 `NotificationCategoryRegistrar` 按需调用。
func registerNotificationCategories(for configs: [ReminderConfig]) {
    UNUserNotificationCenter.current().setNotificationCategories(
        makeNotificationCategories(for: configs)
    )
}

/// 由快照驱动地刷新通知 Category：仅在 (completionLabel, snoozeMinutes)
/// 组合集合变化时重新注册，避免每秒快照刷新造成无谓的 set 调用。
@MainActor
final class NotificationCategoryRegistrar {
    private var registeredSignature: Set<String>?

    func update(snapshot: AppSnapshot?) {
        guard let snapshot else { return }
        let configs = snapshot.reminders.map(\.config)
        let signature = Set(configs.map { config in
            "\(config.completionLabel)|\(config.snoozeDuration.components.seconds)"
        })
        guard signature != registeredSignature else { return }
        registeredSignature = signature
        registerNotificationCategories(for: configs)
    }
}

/// 弱提醒通知内容构建（纯函数，便于测试）。
enum NotificationContentBuilder {
    static func make(
        reminderID: UUID,
        cycleID: UUID,
        effectID: UUID,
        payload: NotificationContent
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = payload.name.isEmpty ? "叮刻" : payload.name
        content.body = payload.message.isEmpty ? "该行动需要你的回应" : payload.message
        content.sound = .default
        content.categoryIdentifier = NotificationCategoryID.make(
            completionLabel: payload.completionLabel,
            snoozeMinutes: payload.snoozeMinutes
        )
        content.userInfo = [
            NotificationUserInfoKey.reminderID: reminderID.uuidString,
            NotificationUserInfoKey.cycleID: cycleID.uuidString,
            NotificationUserInfoKey.effectID: effectID.uuidString,
            NotificationUserInfoKey.schemaVersion: NotificationSchemaVersion.current,
        ]
        return content
    }
}

/// 通知回调解析（纯函数，便于测试）。
enum NotificationIntentParser {
    /// 从 userInfo 解析回执身份；缺失或非法返回 nil。
    static func cycleIdentity(
        from userInfo: [AnyHashable: Any]
    ) -> (reminderID: UUID, cycleID: UUID)? {
        guard
            let reminderIDString = userInfo[NotificationUserInfoKey.reminderID] as? String,
            let cycleIDString = userInfo[NotificationUserInfoKey.cycleID] as? String,
            let reminderID = UUID(uuidString: reminderIDString),
            let cycleID = UUID(uuidString: cycleIDString)
        else { return nil }
        return (reminderID, cycleID)
    }

    /// 把系统动作映射为回执 Intent：
    /// 延后按钮 → snooze；完成按钮与点击正文（Default Action）→ complete。
    static func intent(
        actionIdentifier: String,
        reminderID: UUID,
        cycleID: UUID
    ) -> ReminderIntent {
        if actionIdentifier == NotificationActionID.snooze {
            return .snooze(reminderID: reminderID, cycleID: cycleID)
        }
        return .complete(reminderID: reminderID, cycleID: cycleID)
    }
}

/// 处理通知回调：前台展示 + 完成 / 延后（技术方案 10.4）。
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
        guard let identity = NotificationIntentParser.cycleIdentity(from: userInfo) else {
            completionHandler()
            return
        }

        // 先同步回调完成通知处理，引擎写入放到独立 Task，避免把 sending 闭包传入 Task。
        completionHandler()
        let intent = NotificationIntentParser.intent(
            actionIdentifier: response.actionIdentifier,
            reminderID: identity.reminderID,
            cycleID: identity.cycleID
        )
        Task {
            try? await engine.handle(intent, now: Date())
        }
    }
}

/// 执行 ReminderEffect 的抽象。真实实现走 UNUserNotificationCenter；
/// 测试使用 Mock 记录调用。
protocol EffectExecutor: Sendable {
    func execute(_ effect: ReminderEffect, effectID: UUID) async
}

/// 系统效果执行器：弱提醒通知 + 清理 + 覆盖窗口。
struct SystemEffectExecutor: EffectExecutor {
    private let overlay: any OverlayPresenting
    private let onSubmitResult: (@Sendable (NotificationSubmitResult) -> Void)?

    init(
        overlay: any OverlayPresenting,
        onSubmitResult: (@Sendable (NotificationSubmitResult) -> Void)? = nil
    ) {
        self.overlay = overlay
        self.onSubmitResult = onSubmitResult
    }

    func execute(_ effect: ReminderEffect, effectID: UUID) async {
        switch effect {
        case .sendWeakNotification(let reminderID, let cycleID, let content):
            await sendWeakNotification(
                reminderID: reminderID,
                cycleID: cycleID,
                content: content,
                effectID: effectID
            )
        case .clearNotifications(let reminderID, let cycleID):
            await clear(reminderID: reminderID, cycleID: cycleID)
        case .presentStrongOverlay(let reminderID, let cycleID):
            await overlay.present(reminderID: reminderID, cycleID: cycleID)
        case .dismissStrongOverlay(let reminderID, let cycleID):
            await overlay.dismiss(reminderID: reminderID, cycleID: cycleID)
        }
    }

    private func sendWeakNotification(
        reminderID: UUID,
        cycleID: UUID,
        content: NotificationContent,
        effectID: UUID
    ) async {
        let center = UNUserNotificationCenter.current()
        let logger = Logger(subsystem: "com.loopcue.LoopCue", category: "notification")
        let settings = await center.notificationSettings()
        guard NotificationSubmissionPolicy.isAllowed(settings.authorizationStatus) else {
            // 无权限时系统会直接丢弃提交；明确记录，便于从 Console 定位
            // 「点击立即提醒一次但没弹通知」这类问题（技术方案 17，不记正文）。
            logger.warning("通知权限未开启（raw=\(settings.authorizationStatus.rawValue)），跳过弱提醒提交")
            onSubmitResult?(.skippedUnauthorized)
            return
        }
        let request = UNNotificationRequest(
            identifier: "weak.\(reminderID.uuidString).\(cycleID.uuidString)",
            content: NotificationContentBuilder.make(
                reminderID: reminderID,
                cycleID: cycleID,
                effectID: effectID,
                payload: content
            ),
            trigger: nil
        )
        do {
            try await center.add(request)
            logger.info("弱提醒通知已提交")
            onSubmitResult?(.succeeded(alertEnabled: settings.alertSetting == .enabled))
        } catch {
            logger.error("弱提醒通知提交失败: \(error, privacy: .public)")
            onSubmitResult?(.failed("\(error.localizedDescription)"))
        }
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

/// 通知提交权限判定（纯函数，便于测试）。
enum NotificationSubmissionPolicy {
    static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }
}

/// 一次弱提醒通知提交的结果（供 UI 展示，把「点了没弹」变成可见反馈）。
enum NotificationSubmitResult: Equatable, Sendable {
    case succeeded(alertEnabled: Bool)
    case skippedUnauthorized
    case failed(String)

    var detail: String {
        switch self {
        case .succeeded(let alertEnabled):
            return alertEnabled ? "通知提交成功" : "已提交（横幅关闭，仅进通知中心）"
        case .skippedUnauthorized:
            return "未提交：通知权限未开启"
        case .failed(let message):
            return "通知提交失败：\(message)"
        }
    }

    var isFailure: Bool {
        switch self {
        case .succeeded: return false
        case .skippedUnauthorized, .failed: return true
        }
    }
}
