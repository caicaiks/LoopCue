import Foundation
import os
import UserNotifications

/// 组装生产环境：Store / Engine / Scheduler / EffectDispatcher / Overlay。
@MainActor
final class AppEnvironment {
    let engine: ReminderEngine
    let appModel: AppModel
    private let store: any ReminderStore
    private let scheduler: Scheduler
    private let dispatcher: EffectDispatcher
    private let responseHandler: NotificationResponseHandler
    private var tasks: [Task<Void, Never>] = []

    init() throws {
        let store = try CoreDataReminderStore()
        let engine = ReminderEngine(store: store, timeScale: Self.debugTimeScale)
        let overlay = OverlayPresenter { reminderID, cycleID in
            Task {
                do {
                    try await engine.handle(
                        .complete(reminderID: reminderID, cycleID: cycleID),
                        now: Date()
                    )
                } catch {
                    Logger(subsystem: "com.loopcue.LoopCue", category: "overlay")
                        .error("完成失败: \(error, privacy: .public)")
                }
            }
        } onDismiss: { reminderID, cycleID in
            Task {
                do {
                    try await engine.handle(
                        .dismissOverlay(reminderID: reminderID, cycleID: cycleID),
                        now: Date()
                    )
                } catch {
                    Logger(subsystem: "com.loopcue.LoopCue", category: "overlay")
                        .error("关闭覆盖失败: \(error, privacy: .public)")
                }
            }
        }
        self.store = store
        self.engine = engine
        self.appModel = AppModel(engine: engine)
        self.scheduler = Scheduler(engine: engine)
        self.dispatcher = EffectDispatcher(
            store: store,
            executor: SystemEffectExecutor(overlay: overlay)
        )
        self.responseHandler = NotificationResponseHandler(engine: engine)
        UNUserNotificationCenter.current().delegate = responseHandler
        registerNotificationCategories()
    }

    func start() {
        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                // 每次启动重新计时，而非恢复上一轮状态。
                let snapshot = try await self.engine.freshStart(now: Date())
                self.appModel.set(snapshot)
                if snapshot.reminders.isEmpty {
                    try await self.engine.handle(
                        .create(DefaultReminders.standUp),
                        now: Date()
                    )
                }
                await self.requestNotificationAuthorization()
                await self.refreshNotificationStatus()
                await self.scheduler.start()
                await self.drainLoop()
            } catch {
                Logger(
                    subsystem: "com.loopcue.LoopCue",
                    category: "app"
                ).error("启动失败: \(error, privacy: .public)")
            }
        })
    }

    /// 清空本地数据并重建默认提醒，回到全新的一轮（测试用）。
    func resetForTesting() {
        Task {
            try? await engine.clearAll(now: Date())
            try? await engine.handle(.create(DefaultReminders.standUp), now: Date())
        }
    }

    /// 重新读取通知权限状态并发布到 AppModel（菜单栏每次打开时调用）。
    func checkNotificationPermission() {
        Task {
            await refreshNotificationStatus()
        }
    }

    private func requestNotificationAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            Logger(subsystem: "com.loopcue.LoopCue", category: "notification")
                .info("通知授权结果: granted=\(granted, privacy: .public)")
        } catch {
            Logger(subsystem: "com.loopcue.LoopCue", category: "notification")
                .error("通知授权请求失败: \(error, privacy: .public)")
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let status = settings.authorizationStatus
        let allowed = (status == .authorized || status == .provisional)
        appModel.setNotificationAllowed(allowed)
        appModel.setNotificationStatusDetail(Self.describe(status))
    }

    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "未决定 notDetermined"
        case .denied: return "已拒绝 denied"
        case .authorized: return "已允许 authorized"
        case .provisional: return "临时 provisional"
        @unknown default: return "未知 (\(status.rawValue))"
        }
    }

    private func drainLoop() async {
        while !Task.isCancelled {
            try? await dispatcher.drain()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Debug 构建下时间 10 倍速：5 分钟提醒实际 30 秒触发，方便真机验证。
    /// Release 恒为 1（技术方案 19.6：该能力通过编译条件排除在 Release 之外）。
    private static var debugTimeScale: Double {
        #if DEBUG
        return 10
        #else
        return 1
        #endif
    }
}
