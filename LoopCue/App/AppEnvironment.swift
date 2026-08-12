import Foundation
import os
import UserNotifications

/// 组装生产环境：Store / Engine / Scheduler / EffectDispatcher / Overlay。
@MainActor
final class AppEnvironment {
    let engine: ReminderEngine
    let appModel: AppModel
    private let store: any ReminderStore
    private let overlay: OverlayPresenter
    private let scheduler: Scheduler
    private let dispatcher: EffectDispatcher
    private let responseHandler: NotificationResponseHandler
    private let contextMonitor: SystemContextMonitor
    private let categoryRegistrar: NotificationCategoryRegistrar
    private var tasks: [Task<Void, Never>] = []

    init() throws {
        let store = try CoreDataReminderStore()
        let contextMonitor = SystemContextMonitor()
        let engine = ReminderEngine(
            store: store,
            timeScale: Self.debugTimeScale,
            contextProvider: contextMonitor,
            appState: UserDefaultsAppStateStore()
        )
        self.store = store
        self.engine = engine
        self.contextMonitor = contextMonitor
        self.categoryRegistrar = NotificationCategoryRegistrar()

        let overlay = OverlayPresenter(
            onComplete: { reminderID, cycleID in
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
            },
            onSkip: { reminderID, cycleID in
                Task {
                    do {
                        try await engine.handle(
                            .skip(reminderID: reminderID, cycleID: cycleID),
                            now: Date()
                        )
                    } catch {
                        Logger(subsystem: "com.loopcue.LoopCue", category: "overlay")
                            .error("跳过失败: \(error, privacy: .public)")
                    }
                }
            },
            onSnooze: { reminderID, cycleID in
                Task {
                    do {
                        try await engine.handle(
                            .snooze(reminderID: reminderID, cycleID: cycleID),
                            now: Date()
                        )
                    } catch {
                        Logger(subsystem: "com.loopcue.LoopCue", category: "overlay")
                            .error("延后失败: \(error, privacy: .public)")
                    }
                }
            },
            onDismiss: { reminderID, cycleID in
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
        )
        self.overlay = overlay
        let appModel = AppModel(engine: engine)
        self.appModel = appModel
        // Overlay 消费快照：AppModel 是 stream 唯一消费者，这里做 MainActor 内转发。
        appModel.onSnapshotUpdate = { [weak overlay, weak categoryRegistrar] snapshot in
            overlay?.update(snapshot: snapshot)
            categoryRegistrar?.update(snapshot: snapshot)
        }
        self.scheduler = Scheduler(engine: engine)
        self.dispatcher = EffectDispatcher(
            store: store,
            executor: SystemEffectExecutor(overlay: overlay)
        )
        self.responseHandler = NotificationResponseHandler(engine: engine)
        UNUserNotificationCenter.current().delegate = responseHandler
    }

    func start() {
        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                // 每次启动重新计时，而非恢复上一轮状态。
                let snapshot = try await self.engine.freshStart(now: Date())
                self.appModel.set(snapshot)
                // 首次引导（Onboarding）负责创建第一个提醒与申请通知权限，
                // 不再在启动时自动建模板或抢占权限（PRD 6.1 / 技术方案 10.1）。
                await self.refreshNotificationStatus()
                self.contextMonitor.start { [weak self] in
                    guard let self else { return }
                    Task {
                        try? await self.engine.reconcile(now: Date())
                    }
                }
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
            try? await engine.handle(
                .create(ReminderTemplate.standUp.makeConfig()),
                now: Date()
            )
        }
    }

    /// 重新读取通知权限状态并发布到 AppModel（菜单栏每次打开时调用）。
    func checkNotificationPermission() {
        Task {
            await refreshNotificationStatus()
        }
    }

    /// 按需请求通知权限（Onboarding 创建首个提醒后调用，技术方案 10.1）。
    func requestNotificationAuthorization() async {
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
