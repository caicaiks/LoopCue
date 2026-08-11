import Foundation

/// 最小调度器：周期性唤醒 Engine.reconcile。
///
/// Timer 不是时间事实来源，只负责触发；真实状态由 Engine 依据
/// 持久化时间点推导（技术方案 8.1）。睡眠 / 锁屏 / 闲置 / 生效时段
/// 门控属于 M1-B，本阶段不做。
actor Scheduler {
    private let engine: ReminderEngine
    private let tickInterval: Duration
    private var task: Task<Void, Never>?

    init(engine: ReminderEngine, tickInterval: Duration = .seconds(1)) {
        self.engine = engine
        self.tickInterval = tickInterval
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func tick() async {
        try? await engine.reconcile(now: Date())
        try? await Task.sleep(for: tickInterval)
    }
}

