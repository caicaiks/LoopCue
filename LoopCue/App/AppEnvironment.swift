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
    private var tasks: [Task<Void, Never>] = []

    init() throws {
        let store = try CoreDataReminderStore()
        let engine = ReminderEngine(store: store)
        let overlay = OverlayPresenter { reminderID, cycleID in
            Task {
                try? await engine.handle(
                    .complete(reminderID: reminderID, cycleID: cycleID),
                    now: Date()
                )
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
    }

    func start() {
        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.engine.start(now: Date())
                self.appModel.set(snapshot)
                if snapshot.reminders.isEmpty {
                    try await self.engine.handle(
                        .create(DefaultReminders.standUp),
                        now: Date()
                    )
                }
                await self.requestNotificationAuthorization()
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

    private func requestNotificationAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    private func drainLoop() async {
        while !Task.isCancelled {
            try? await dispatcher.drain()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

