import Foundation

/// 提供给 UI 层的不可变快照（技术方案 14.1）。
///
/// UI 只读取快照，禁止自行推导业务状态。
struct ReminderSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let config: ReminderConfig
    let phase: CyclePhase?
    let cycleID: UUID?
    let activeElapsed: Duration
    let escalationElapsed: Duration
    let snoozeCount: Int

    /// 距离弱提醒的剩余有效时长（仅 Counting 阶段）。
    var remainingToWeak: Duration? {
        guard phase == .counting else { return nil }
        return max(.zero, config.interval - activeElapsed)
    }
}

/// 菜单栏「下一个提醒」投影：剩余时间最近的 Counting 提醒。
struct NextReminderProjection: Equatable, Sendable {
    let reminderID: UUID
    let name: String
    let icon: ReminderIcon
    let remainingToWeak: Duration
}

/// 「等待回应」列表项：弱提醒已发出、延后中或强提醒展示中。
struct PendingReminderSnapshot: Equatable, Sendable {
    let reminderID: UUID
    let cycleID: UUID
    let name: String
    let icon: ReminderIcon
    let phase: CyclePhase
    /// 距离下一次升级/再提醒的剩余时长（无升级配置或正在展示时为 nil）。
    let remainingToStrong: Duration?
    let snoozeCount: Int
    let maxSnoozeCount: Int
}

/// 强提醒队列项（技术方案 11.3 排序规则）。
struct StrongReminderSnapshot: Equatable, Sendable {
    let reminderID: UUID
    let cycleID: UUID
    let name: String
    let icon: ReminderIcon
    let message: String
    let completionLabel: String
    let strongTriggeredAt: Date?
    let createdAt: Date
}

struct AppSnapshot: Equatable, Sendable {
    let reminders: [ReminderSnapshot]
    /// 菜单栏下一项投影。
    let nextReminder: NextReminderProjection?
    /// 等待回应列表。
    let pendingResponses: [PendingReminderSnapshot]
    /// 强提醒队列（只展示一个主卡片，其余等待依次处理）。
    let strongQueue: [StrongReminderSnapshot]
    let now: Date

    static func make(
        from storedReminders: [StoredReminder],
        now: Date
    ) -> AppSnapshot {
        let reminders = storedReminders.map { stored -> ReminderSnapshot in
            ReminderSnapshot(
                id: stored.config.id,
                config: stored.config,
                phase: stored.cycle?.phase,
                cycleID: stored.cycle?.id,
                activeElapsed: stored.cycle?.activeElapsed ?? .zero,
                escalationElapsed: stored.cycle?.escalationElapsed ?? .zero,
                snoozeCount: stored.cycle?.snoozeCount ?? 0
            )
        }
        let projected = Self.project(storedReminders, now: now)
        return AppSnapshot(
            reminders: reminders,
            nextReminder: projected.next,
            pendingResponses: projected.pending,
            strongQueue: projected.strong,
            now: now
        )
    }

    /// 纯投影函数：根据持久化状态推导菜单栏与列表展示所需的派生数据。
    static func project(
        _ storedReminders: [StoredReminder],
        now: Date
    ) -> (
        next: NextReminderProjection?,
        pending: [PendingReminderSnapshot],
        strong: [StrongReminderSnapshot]
    ) {
        var next: NextReminderProjection?
        var pending: [PendingReminderSnapshot] = []
        var strong: [StrongReminderSnapshot] = []

        for stored in storedReminders {
            let config = stored.config
            guard let cycle = stored.cycle else { continue }

            switch cycle.phase {
            case .counting:
                guard config.isEnabled else { continue }
                let remaining = max(.zero, cycle.policy.interval - cycle.activeElapsed)
                if next == nil || remaining < next!.remainingToWeak {
                    next = NextReminderProjection(
                        reminderID: config.id,
                        name: config.name,
                        icon: config.icon,
                        remainingToWeak: remaining
                    )
                }

            case .weakPending, .snoozed, .strongPending:
                let remainingToStrong: Duration?
                switch cycle.phase {
                case .weakPending:
                    remainingToStrong = cycle.policy.escalationDelay.map {
                        max(.zero, $0 - cycle.escalationElapsed)
                    }
                case .snoozed:
                    remainingToStrong = cycle.snoozeRemaining
                case .strongPending:
                    remainingToStrong = .zero
                case .counting:
                    remainingToStrong = nil
                }
                pending.append(
                    PendingReminderSnapshot(
                        reminderID: config.id,
                        cycleID: cycle.id,
                        name: config.name,
                        icon: config.icon,
                        phase: cycle.phase,
                        remainingToStrong: remainingToStrong,
                        snoozeCount: cycle.snoozeCount,
                        maxSnoozeCount: cycle.policy.maxSnoozeCount
                    )
                )

                if cycle.phase == .strongPending {
                    strong.append(
                        StrongReminderSnapshot(
                            reminderID: config.id,
                            cycleID: cycle.id,
                            name: config.name,
                            icon: config.icon,
                            message: config.message,
                            completionLabel: config.completionLabel,
                            strongTriggeredAt: cycle.strongTriggeredAt,
                            createdAt: config.createdAt
                        )
                    )
                }
            }
        }

        strong.sort { lhs, rhs in
            let a = lhs.strongTriggeredAt ?? .distantFuture
            let b = rhs.strongTriggeredAt ?? .distantFuture
            if a != b { return a < b }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.reminderID.uuidString < rhs.reminderID.uuidString
        }

        return (next: next, pending: pending, strong: strong)
    }
}
