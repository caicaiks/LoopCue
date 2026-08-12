import Foundation

/// 调度策略：计算下一次 `ReminderEngine.reconcile` 的唤醒间隔
/// （技术方案 8.7 / 18 能耗预算）。
///
/// 原则：
/// - 事件点（弱提醒、升级、延后结束、抑制结束、暂停截止、生效时段边界）
///   到期前按事件点唤醒；
/// - 存在正在计时或等待回应的提醒时，至多 30 秒做一次轻量 checkpoint
///   （Engine 在门控期间不写库，唤醒只是重新结算与刷新快照）；
/// - 无提醒或全部门控时只按边界/暂停唤醒，最长 60 秒空轮询兜底。
enum SchedulerPolicy {
    static let checkpointInterval: Duration = .seconds(30)
    static let idlePollInterval: Duration = .seconds(60)
    static let minimumInterval: Duration = .seconds(1)

    static func nextWakeDelay(
        from snapshot: AppSnapshot,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Duration {
        var candidates: [Duration] = []

        // 1) 下一弱提醒（counting 剩余有效时长）。
        if let next = snapshot.nextReminder {
            candidates.append(next.remainingToWeak)
        }

        // 2) 等待回应：升级 / 延后结束 / 抑制结束。
        for pending in snapshot.pendingResponses {
            if let remaining = pending.remainingToStrong {
                candidates.append(remaining)
            }
        }

        // 3) 单项暂停截止与生效时段边界（墙上时间）。
        for reminder in snapshot.reminders {
            if let until = reminder.pauseUntil, until != .distantFuture {
                candidates.append(.seconds(Int64(until.timeIntervalSince(now))))
            }
            if let boundary = nextScheduleBoundary(
                schedule: reminder.config.activeSchedule,
                from: now,
                calendar: calendar
            ) {
                candidates.append(.seconds(Int64(boundary.timeIntervalSince(now))))
            }
        }

        // 4) 全局暂停截止。
        if let until = snapshot.globalPauseUntil, until != .distantFuture {
            candidates.append(.seconds(Int64(until.timeIntervalSince(now))))
        }

        let eventDelay = candidates
            .filter { $0 > .zero }
            .min() ?? (hasActiveReminder(snapshot) ? checkpointInterval : idlePollInterval)

        if hasActiveReminder(snapshot) {
            // 有进行中的提醒：事件点与 30 秒 checkpoint 取早者。
            return max(minimumInterval, min(checkpointInterval, eventDelay))
        }
        // 无进行中的提醒：只按边界/暂停唤醒，兜底 60 秒。
        return max(minimumInterval, min(idlePollInterval, eventDelay))
    }

    /// 是否存在需要周期性结算的提醒（启用且处于任一业务阶段）。
    static func hasActiveReminder(_ snapshot: AppSnapshot) -> Bool {
        snapshot.reminders.contains { $0.config.isEnabled && $0.phase != nil }
    }

    /// 下一个生效时段边界（进入或离开生效时段的墙上时间点）。
    /// `.alwaysOn` 或未来 8 天内无生效时段时返回 nil。
    static func nextScheduleBoundary(
        schedule: ActiveSchedule,
        from now: Date,
        calendar: Calendar
    ) -> Date? {
        guard schedule != .alwaysOn,
              let horizon = calendar.date(byAdding: .day, value: 8, to: now)
        else { return nil }
        let segments = ActiveSchedule.activeSegments(
            schedule,
            from: now,
            to: horizon,
            calendar: calendar
        )
        guard let first = segments.first else { return nil }
        if now < first.0 {
            return first.0 // 尚未进入生效时段：下次进入。
        }
        if now < first.1 {
            return first.1 // 正在生效时段内：下次离开。
        }
        return first.0
    }
}
