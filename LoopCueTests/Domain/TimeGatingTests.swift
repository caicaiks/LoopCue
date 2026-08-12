import XCTest
@testable import LoopCue

final class TimeGatingTests: XCTestCase {
    private var calendar: Calendar { fixedCalendar() }
    /// 周一 09:00（UTC）。
    private var t0: Date { date(2026, 8, 17, 9, 0, calendar: calendar) }

    private func effective(
        from start: Date,
        to end: Date,
        schedule: ActiveSchedule = .alwaysOn,
        isAwake: Bool = true,
        isSessionActive: Bool = true,
        pauseUntil: Date? = nil,
        awayPolicy: AwayPolicy = .pause(threshold: .minutes(5)),
        lastInputAt: Date?
    ) -> Duration {
        TimeGating.effectiveDuration(
            from: start,
            to: end,
            schedule: schedule,
            calendar: calendar,
            isAwake: isAwake,
            isSessionActive: isSessionActive,
            pauseUntil: pauseUntil,
            awayPolicy: awayPolicy,
            lastInputAt: lastInputAt
        )
    }

    func testFullWindowCountsWhenAllGatesOpen() {
        let duration = effective(
            from: t0, to: t0.addingTimeInterval(600), lastInputAt: t0.addingTimeInterval(600)
        )
        XCTAssertEqual(duration, .seconds(600))
    }

    func testSleepAndLockedFreezeTime() {
        let end = t0.addingTimeInterval(600)
        XCTAssertEqual(
            effective(from: t0, to: end, isAwake: false, lastInputAt: end), .zero
        )
        XCTAssertEqual(
            effective(from: t0, to: end, isSessionActive: false, lastInputAt: end), .zero
        )
    }

    func testNonActiveScheduleFreezesTime() {
        let schedule = ActiveSchedule(weekdayMask: [1], startMinute: 10 * 60, endMinute: 12 * 60)
        // 9:00 → 10:00 全在生效时段之前
        let duration = effective(
            from: t0, to: t0.addingTimeInterval(3600),
            schedule: schedule,
            lastInputAt: t0.addingTimeInterval(3600)
        )
        XCTAssertEqual(duration, .zero)
    }

    func testScheduleCountsOnlyActivePart() {
        let schedule = ActiveSchedule(weekdayMask: [1], startMinute: 9 * 60, endMinute: 10 * 60)
        // 9:00 → 11:00：只累计 9:00-10:00
        let duration = effective(
            from: t0, to: t0.addingTimeInterval(7200),
            schedule: schedule,
            lastInputAt: t0.addingTimeInterval(7200)
        )
        XCTAssertEqual(duration, .hours(1))
    }

    func testPauseFreezesAndSplitsAtDeadline() {
        // 契约：pauseUntil 表示暂停覆盖 [windowStart, pauseUntil)。
        // Engine 保证 checkpoint（windowStart）≥ 暂停起点。
        let end = t0.addingTimeInterval(600)
        // 暂停到 9:05 → 只累计 9:05-9:10
        XCTAssertEqual(
            effective(from: t0, to: end, pauseUntil: t0.addingTimeInterval(300), lastInputAt: end),
            .seconds(300)
        )
        // 暂停到 9:06 → 只累计 9:06-9:10
        XCTAssertEqual(
            effective(from: t0, to: end, pauseUntil: t0.addingTimeInterval(360), lastInputAt: end),
            .seconds(240)
        )
        // 暂停在窗口开始前已结束 → 全累计
        XCTAssertEqual(
            effective(from: t0, to: end, pauseUntil: t0.addingTimeInterval(-60), lastInputAt: end),
            .seconds(600)
        )
        // 暂停覆盖整个窗口 → 0
        XCTAssertEqual(
            effective(from: t0, to: end, pauseUntil: end.addingTimeInterval(60), lastInputAt: end),
            .zero
        )
    }

    func testIdleCountsOnlyUpToAwayBoundary() {
        // 用户在 9:30 最后输入，阈值 5 分钟 → 9:35 起离开
        let lastInput = date(2026, 8, 17, 9, 30, calendar: calendar)
        let end = date(2026, 8, 17, 9, 40, calendar: calendar)
        let duration = effective(from: t0, to: end, lastInputAt: lastInput)
        XCTAssertEqual(duration, .minutes(35)) // 9:00 → 9:35
    }

    func testNoInputMeansNoTime() {
        XCTAssertEqual(effective(from: t0, to: t0.addingTimeInterval(600), lastInputAt: nil), .zero)
    }

    func testGatesCompose() {
        // 综合：生效时段 9:00-10:00；暂停覆盖 [9:00, 9:10]；
        // 用户 9:20 最后输入（阈值 5 分 → 9:25 离开）。
        // 有效 = 在场 ∩ 未暂停 ∩ 生效时段 = [9:10, 9:25] = 15 分钟
        let schedule = ActiveSchedule(weekdayMask: [1], startMinute: 9 * 60, endMinute: 10 * 60)
        let pauseUntil = date(2026, 8, 17, 9, 10, calendar: calendar)
        let lastInput = date(2026, 8, 17, 9, 20, calendar: calendar)
        let end = date(2026, 8, 17, 11, 0, calendar: calendar)
        let duration = effective(
            from: t0, to: end, schedule: schedule,
            pauseUntil: pauseUntil, lastInputAt: lastInput
        )
        XCTAssertEqual(duration, .minutes(15))
    }
}
