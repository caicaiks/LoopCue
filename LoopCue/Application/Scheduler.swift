import Foundation
import os

/// 事件点调度器：按下一事件/checkpoint 唤醒 Engine.reconcile
/// （技术方案 8.7 / 18）。
///
/// Timer 不是时间事实来源，只负责触发；真实状态由 Engine 依据
/// 持久化时间点推导。唤醒间隔由 SchedulerPolicy 依据最新快照计算：
/// 弱提醒/升级/延后结束/抑制结束/暂停截止/生效时段边界 + 30 秒
/// checkpoint；睡眠、锁屏、闲置等上下文事件仍由 SystemContextMonitor
/// 直接驱动 reconcile。
actor Scheduler {
    private let engine: ReminderEngine
    private var task: Task<Void, Never>?
    /// 子系统日志（技术方案 17）：只记录唤醒原因与间隔，不记录提醒内容。
    private static let logger = Logger(
        subsystem: "com.loopcue.LoopCue",
        category: "scheduler"
    )

    init(engine: ReminderEngine) {
        self.engine = engine
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
        let delay = await nextWakeDelay() ?? SchedulerPolicy.checkpointInterval
        Self.logger.debug("下次唤醒间隔: \(delay.components.seconds, privacy: .public)s")
        try? await Task.sleep(for: delay)
    }

    private func nextWakeDelay() async -> Duration? {
        let now = Date()
        guard let snapshot = try? await engine.currentSnapshot(now: now) else {
            return nil
        }
        return SchedulerPolicy.nextWakeDelay(from: snapshot, now: now)
    }
}
