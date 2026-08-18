import XCTest
@testable import LoopCue

final class SchedulerPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 4_000_000)

    private func makeConfig(
        id: UUID = UUID(),
        name: String = "测试",
        interval: Duration = .minutes(5),
        escalationDelay: Duration? = .minutes(2),
        activeSchedule: ActiveSchedule = .alwaysOn,
        isEnabled: Bool = true
    ) -> ReminderConfig {
        ReminderConfig(
            id: id,
            name: name,
            interval: interval,
            escalationDelay: escalationDelay,
            activeSchedule: activeSchedule,
            isEnabled: isEnabled
        )
    }

    private func makeCycle(config: ReminderConfig) -> ReminderCycle {
        ReminderCycle(
            reminderID: config.id,
            policy: CyclePolicySnapshot(config: config),
            startedAt: now
        )
    }

    private func advance(_ cycle: ReminderCycle, by duration: Duration) -> ReminderCycle {
        ReminderReducer.advance(cycle, by: duration, now: now).cycle
    }

    private func snapshot(
        _ stored: [StoredReminder],
        globalPauseUntil: Date? = nil
    ) -> AppSnapshot {
        var snapshot = AppSnapshot.make(from: stored, now: now)
        snapshot.globalPauseUntil = globalPauseUntil
        return snapshot
    }

    func testCountingReminderWakesAtEventOrCheckpoint() {
        let config = makeConfig(interval: .minutes(5))
        let fresh = snapshot([StoredReminder(config: config, cycle: makeCycle(config: config))])
        // 事件 5 分钟后，checkpoint 30 秒先到。
        XCTAssertEqual(
            SchedulerPolicy.nextWakeDelay(from: fresh, now: now),
            .seconds(30)
        )

        // 事件还剩 10 秒 → 按事件点唤醒。
        let nearEvent = advance(makeCycle(config: config), by: .seconds(4 * 60 + 50))
        let nearSnapshot = snapshot([StoredReminder(config: config, cycle: nearEvent)])
        XCTAssertEqual(
            SchedulerPolicy.nextWakeDelay(from: nearSnapshot, now: now),
            .seconds(10)
        )
    }

    func testWeakPendingWakesAtEscalationEnd() {
        let config = makeConfig(interval: .minutes(5), escalationDelay: .minutes(2))
        let weak = advance(makeCycle(config: config), by: .minutes(5))
        XCTAssertEqual(weak.phase, .weakPending)

        // 升级还剩 5 秒 → 5 秒后唤醒。
        let near = advance(weak, by: .seconds(60 + 55))
        let nearSnapshot = snapshot([StoredReminder(config: config, cycle: near)])
        XCTAssertEqual(
            SchedulerPolicy.nextWakeDelay(from: nearSnapshot, now: now),
            .seconds(5)
        )
    }

    func testNoActiveReminderFallsBackToIdlePoll() {
        XCTAssertEqual(
            SchedulerPolicy.nextWakeDelay(from: snapshot([]), now: now),
            SchedulerPolicy.idlePollInterval
        )

        let disabled = makeConfig(isEnabled: false)
        let disabledSnapshot = snapshot([
            StoredReminder(config: disabled, cycle: makeCycle(config: disabled)),
        ])
        XCTAssertEqual(
            SchedulerPolicy.nextWakeDelay(from: disabledSnapshot, now: now),
            SchedulerPolicy.idlePollInterval
        )
    }

    func testPauseDeadlineCapsWake() {
        let config = makeConfig()
        let pausedUntil = now.addingTimeInterval(15)
        let s = snapshot(
            [StoredReminder(config: config, cycle: makeCycle(config: config))],
            globalPauseUntil: pausedUntil
        )
        XCTAssertEqual(
            SchedulerPolicy.nextWakeDelay(from: s, now: now),
            .seconds(15)
        )
    }

    func testOutOfScheduleWakesAtBoundaryWhenSoon() {
        let config = makeConfig(activeSchedule: ActiveSchedule(
            weekdayMask: [1],
            startMinute: 9 * 60,
            endMinute: 18 * 60
        ))
        // 周一 10:00：生效时段内，边界为当天 18:00。
        let monday10 = date(2026, 8, 17, 10, 0, calendar: fixedCalendar())
        let boundary = SchedulerPolicy.nextScheduleBoundary(
            schedule: config.activeSchedule,
            from: monday10,
            calendar: fixedCalendar()
        )
        XCTAssertEqual(boundary, date(2026, 8, 17, 18, 0, calendar: fixedCalendar()))

        // 周一 20:00：时段外，边界为下周一 09:00。
        let monday20 = date(2026, 8, 17, 20, 0, calendar: fixedCalendar())
        let next = SchedulerPolicy.nextScheduleBoundary(
            schedule: config.activeSchedule,
            from: monday20,
            calendar: fixedCalendar()
        )
        let nextMonday9 = fixedCalendar().date(
            byAdding: .day,
            value: 7,
            to: date(2026, 8, 17, 9, 0, calendar: fixedCalendar())
        )
        XCTAssertEqual(next, nextMonday9)

        // 生效时段（00:00–00:10）边界在 20 秒后且存在进行中的提醒 → 按边界唤醒。
        let configShort = makeConfig(activeSchedule: ActiveSchedule(
            weekdayMask: [1],
            startMinute: 0,
            endMinute: 10
        ))
        let cycle = makeCycle(config: configShort)
        let snapshot = snapshot([StoredReminder(config: configShort, cycle: cycle)])
        let justBeforeWindowEnd = date(
            2026, 8, 17, 0, 9,
            calendar: fixedCalendar()
        ).addingTimeInterval(40) // 00:09:40，距离 00:10 边界 20 秒
        let delay = SchedulerPolicy.nextWakeDelay(
            from: snapshot,
            now: justBeforeWindowEnd,
            calendar: fixedCalendar()
        )
        XCTAssertEqual(delay, .seconds(20))
    }

    func testAlwaysOnHasNoScheduleBoundary() {
        XCTAssertNil(SchedulerPolicy.nextScheduleBoundary(
            schedule: .alwaysOn,
            from: now,
            calendar: fixedCalendar()
        ))
    }
}
