import Foundation

/// 一次归约的结果：当前轮、事件与待执行副作用。
struct Reduction: Equatable, Sendable {
    let cycle: ReminderCycle
    let events: [ReminderEvent]
    let effects: [ReminderEffect]

    static func unchanged(_ cycle: ReminderCycle) -> Reduction {
        Reduction(cycle: cycle, events: [], effects: [])
    }
}

/// 纯领域状态机（技术方案 7、8.4）。
///
/// 不依赖 SwiftUI / AppKit / Core Data；时间由调用方注入，保证可单测。
/// 只处理「基础阶段」的转换；暂停、睡眠、锁屏、闲置与非生效时段是阶段
/// 外部的时间门控，由 Scheduler / Engine 判断后传入有效时长。
enum ReminderReducer {
    /// 推进一段「有效使用时长」。delta 会被切分成多个时间片，
    /// 允许一段 delta 连续跨过弱提醒与强提醒两个阈值（技术方案 8.4）。
    static func advance(_ cycle: ReminderCycle, by delta: Duration, now: Date) -> Reduction {
        precondition(delta >= .zero, "delta 不能为负")
        guard delta > .zero else { return .unchanged(cycle) }

        var cycle = cycle
        var events: [ReminderEvent] = []
        var effects: [ReminderEffect] = []
        var remaining = delta

        while remaining > .zero {
            switch cycle.phase {
            case .counting:
                let step = min(remaining, max(.zero, cycle.policy.interval - cycle.activeElapsed))
                cycle.activeElapsed += step
                remaining -= step
                if cycle.activeElapsed >= cycle.policy.interval {
                    cycle.phase = .weakPending
                    cycle.weakTriggeredAt = now
                    events.append(.init(reminderID: cycle.reminderID, cycleID: cycle.id, type: .weakTriggered, occurredAt: now))
                    effects.append(.sendWeakNotification(reminderID: cycle.reminderID, cycleID: cycle.id))
                }

            case .weakPending:
                guard let delay = cycle.policy.escalationDelay else {
                    // 未开启升级：只等待用户回执，不消耗时间。
                    remaining = .zero
                    break
                }
                let step = min(remaining, max(.zero, delay - cycle.escalationElapsed))
                cycle.escalationElapsed += step
                remaining -= step
                if cycle.escalationElapsed >= delay {
                    cycle.phase = .strongPending
                    cycle.strongTriggeredAt = now
                    events.append(.init(reminderID: cycle.reminderID, cycleID: cycle.id, type: .strongTriggered, occurredAt: now))
                    effects.append(.presentStrongOverlay(reminderID: cycle.reminderID, cycleID: cycle.id))
                }

            case .snoozed:
                let remainingSnooze = cycle.snoozeRemaining ?? .zero
                let step = min(remaining, remainingSnooze)
                cycle.snoozeRemaining = remainingSnooze - step
                remaining -= step
                if cycle.snoozeRemaining! <= .zero {
                    cycle.snoozeRemaining = nil
                    cycle.phase = .weakPending
                    cycle.weakTriggeredAt = now
                    events.append(.init(reminderID: cycle.reminderID, cycleID: cycle.id, type: .weakRepeated, occurredAt: now))
                    effects.append(.sendWeakNotification(reminderID: cycle.reminderID, cycleID: cycle.id))
                }

            case .strongPending:
                guard let suppression = cycle.overlaySuppressionRemaining else {
                    // 覆盖窗口正在展示，等待回执。
                    remaining = .zero
                    break
                }
                let step = min(remaining, suppression)
                cycle.overlaySuppressionRemaining = suppression - step
                remaining -= step
                if cycle.overlaySuppressionRemaining! <= .zero {
                    cycle.overlaySuppressionRemaining = nil
                    events.append(.init(reminderID: cycle.reminderID, cycleID: cycle.id, type: .strongRepeated, occurredAt: now))
                    effects.append(.presentStrongOverlay(reminderID: cycle.reminderID, cycleID: cycle.id))
                }
            }
        }

        return Reduction(cycle: cycle, events: events, effects: effects)
    }

    /// 应用带回执的 Intent。cycleID 与当前轮不一致时返回无副作用的归约。
    static func apply(_ intent: ReminderIntent, to cycle: ReminderCycle, now: Date) -> Reduction {
        switch intent {
        case .create, .update, .delete, .setEnabled:
            // 配置类 Intent 不改变轮次状态，由 Engine 负责。
            return .unchanged(cycle)
        case .complete(let reminderID, let cycleID),
             .snooze(let reminderID, let cycleID),
             .skip(let reminderID, let cycleID),
             .triggerWeakNow(let reminderID, let cycleID),
             .dismissOverlay(let reminderID, let cycleID):
            guard cycle.reminderID == reminderID, cycle.id == cycleID else {
                return .unchanged(cycle) // stale cycle，无副作用
            }
        }

        switch intent {
        case .complete(let reminderID, let cycleID):
            return finishedCycle(
                after: cycle,
                type: .completed,
                reminderID: reminderID,
                cycleID: cycleID,
                now: now
            )

        case .skip(let reminderID, let cycleID):
            return finishedCycle(
                after: cycle,
                type: .skipped,
                reminderID: reminderID,
                cycleID: cycleID,
                now: now
            )

        case .snooze(let reminderID, let cycleID):
            guard cycle.phase != .counting, cycle.snoozeCount < cycle.policy.maxSnoozeCount else {
                return .unchanged(cycle)
            }
            var cycle = cycle
            cycle.phase = .snoozed
            cycle.snoozeCount += 1
            cycle.snoozeRemaining = cycle.policy.snoozeDuration
            cycle.overlaySuppressionRemaining = nil
            return Reduction(
                cycle: cycle,
                events: [.init(reminderID: reminderID, cycleID: cycleID, type: .snoozed, occurredAt: now)],
                effects: [
                    .clearNotifications(reminderID: reminderID, cycleID: cycleID),
                    .dismissStrongOverlay(reminderID: reminderID, cycleID: cycleID),
                ]
            )

        case .triggerWeakNow(let reminderID, let cycleID):
            guard cycle.phase == .counting else { return .unchanged(cycle) }
            var cycle = cycle
            cycle.phase = .weakPending
            cycle.activeElapsed = cycle.policy.interval
            cycle.weakTriggeredAt = now
            return Reduction(
                cycle: cycle,
                events: [.init(reminderID: reminderID, cycleID: cycleID, type: .weakTriggered, occurredAt: now)],
                effects: [.sendWeakNotification(reminderID: reminderID, cycleID: cycleID)]
            )

        case .dismissOverlay(let reminderID, let cycleID):
            guard cycle.phase == .strongPending, cycle.overlaySuppressionRemaining == nil else {
                return .unchanged(cycle)
            }
            var cycle = cycle
            cycle.overlaySuppressionRemaining = .minutes(5)
            return Reduction(
                cycle: cycle,
                events: [.init(reminderID: reminderID, cycleID: cycleID, type: .overlayDismissed, occurredAt: now)],
                effects: [.dismissStrongOverlay(reminderID: reminderID, cycleID: cycleID)]
            )

        case .create, .update, .delete, .setEnabled:
            return .unchanged(cycle)
        }
    }

    /// 记录一次用户输入（在场证明）。
    static func noteUserActivity(_ cycle: ReminderCycle) -> ReminderCycle {
        var cycle = cycle
        cycle.hasObservedPresence = true
        return cycle
    }

    /// 处理闲置状态。只有「先观察到在场，再离开达到阈值」才自动完成（技术方案 6.4）。
    static func applyIdle(_ cycle: ReminderCycle, idleDuration: Duration, now: Date) -> Reduction {
        guard case .complete(let threshold) = cycle.policy.awayPolicy else {
            return .unchanged(cycle) // pause 策略由 Engine 暂停计时
        }
        guard cycle.phase == .counting, cycle.hasObservedPresence, idleDuration >= threshold else {
            return .unchanged(cycle)
        }
        let reminderID = cycle.reminderID
        let cycleID = cycle.id
        let newCycle = newCycle(after: cycle, startedAt: now)
        return Reduction(
            cycle: newCycle,
            events: [.init(reminderID: reminderID, cycleID: cycleID, type: .autoCompleted, occurredAt: now)],
            effects: [
                .clearNotifications(reminderID: reminderID, cycleID: cycleID),
                .dismissStrongOverlay(reminderID: reminderID, cycleID: cycleID),
            ]
        )
    }

    /// 完成/跳过/自动完成统一走「终止旧轮 + 创建新轮」。
    private static func finishedCycle(
        after cycle: ReminderCycle,
        type: ReminderEventType,
        reminderID: UUID,
        cycleID: UUID,
        now: Date
    ) -> Reduction {
        let newCycle = newCycle(after: cycle, startedAt: now)
        return Reduction(
            cycle: newCycle,
            events: [.init(reminderID: reminderID, cycleID: cycleID, type: type, occurredAt: now)],
            effects: [
                .clearNotifications(reminderID: reminderID, cycleID: cycleID),
                .dismissStrongOverlay(reminderID: reminderID, cycleID: cycleID),
            ]
        )
    }

    private static func newCycle(after cycle: ReminderCycle, startedAt: Date) -> ReminderCycle {
        ReminderCycle(reminderID: cycle.reminderID, policy: cycle.policy, startedAt: startedAt)
    }
}
