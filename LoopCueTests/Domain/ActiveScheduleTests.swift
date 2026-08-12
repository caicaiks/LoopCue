import XCTest
@testable import LoopCue

final class ActiveScheduleTests: XCTestCase {
    private var calendar: Calendar { fixedCalendar() }

    func testIsoWeekdayMapping() {
        // 2026-08-17 = 周一 … 2026-08-23 = 周日
        let cases: [(Int, Int, Int, Int)] = [
            (2026, 8, 17, 1),
            (2026, 8, 18, 2),
            (2026, 8, 19, 3),
            (2026, 8, 20, 4),
            (2026, 8, 21, 5),
            (2026, 8, 22, 6),
            (2026, 8, 23, 7),
        ]
        for (y, m, d, expected) in cases {
            let day = date(y, m, d, 0, calendar: calendar)
            XCTAssertEqual(ActiveSchedule.isoWeekday(day, calendar: calendar), expected)
        }
    }

    func testIsActiveByWeekdayAndTime() {
        let schedule = ActiveSchedule(
            weekdayMask: [1, 3, 5],
            startMinute: 9 * 60,
            endMinute: 18 * 60
        )
        // 周一 10:00 生效
        XCTAssertTrue(ActiveSchedule.isActive(
            schedule, at: date(2026, 8, 17, 10, calendar: calendar), calendar: calendar
        ))
        // 周二 10:00 不在工作日
        XCTAssertFalse(ActiveSchedule.isActive(
            schedule, at: date(2026, 8, 18, 10, calendar: calendar), calendar: calendar
        ))
        // 周一 08:00 在生效时段前
        XCTAssertFalse(ActiveSchedule.isActive(
            schedule, at: date(2026, 8, 17, 8, calendar: calendar), calendar: calendar
        ))
        // 周一 18:00 是结束边界（不包含）
        XCTAssertFalse(ActiveSchedule.isActive(
            schedule, at: date(2026, 8, 17, 18, calendar: calendar), calendar: calendar
        ))
        // 周一 17:59 生效
        XCTAssertTrue(ActiveSchedule.isActive(
            schedule, at: date(2026, 8, 17, 17, 59, calendar: calendar), calendar: calendar
        ))
    }

    func testActiveSegmentsCountOnlyActiveWindow() {
        let schedule = ActiveSchedule(
            weekdayMask: [1],
            startMinute: 9 * 60,
            endMinute: 12 * 60
        )
        let start = date(2026, 8, 17, 8, 0, calendar: calendar)
        let end = date(2026, 8, 17, 13, 0, calendar: calendar)
        let segments = ActiveSchedule.activeSegments(schedule, from: start, to: end, calendar: calendar)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].0, date(2026, 8, 17, 9, 0, calendar: calendar))
        XCTAssertEqual(segments[0].1, date(2026, 8, 17, 12, 0, calendar: calendar))
    }

    func testActiveSegmentsClipsPartialWindow() {
        let schedule = ActiveSchedule(
            weekdayMask: [1],
            startMinute: 9 * 60,
            endMinute: 18 * 60
        )
        let start = date(2026, 8, 17, 10, 0, calendar: calendar)
        let end = date(2026, 8, 17, 11, 0, calendar: calendar)
        let segments = ActiveSchedule.activeSegments(schedule, from: start, to: end, calendar: calendar)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].0, start)
        XCTAssertEqual(segments[0].1, end)
    }

    func testActiveSegmentsAcrossMidnight() {
        let schedule = ActiveSchedule(
            weekdayMask: [1, 2],
            startMinute: 9 * 60,
            endMinute: 18 * 60
        )
        // 周一 08:00 → 周二 10:00：交集 = 周一 9-18 + 周二 9-10
        let start = date(2026, 8, 17, 8, 0, calendar: calendar)
        let end = date(2026, 8, 18, 10, 0, calendar: calendar)
        let segments = ActiveSchedule.activeSegments(schedule, from: start, to: end, calendar: calendar)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].0, date(2026, 8, 17, 9, 0, calendar: calendar))
        XCTAssertEqual(segments[0].1, date(2026, 8, 17, 18, 0, calendar: calendar))
        XCTAssertEqual(segments[1].0, date(2026, 8, 18, 9, 0, calendar: calendar))
        XCTAssertEqual(segments[1].1, date(2026, 8, 18, 10, 0, calendar: calendar))
    }

    func testActiveSegmentsEmptyOutsideWeekdayWindow() {
        let schedule = ActiveSchedule(
            weekdayMask: [3],
            startMinute: 9 * 60,
            endMinute: 18 * 60
        )
        // 周一 20:00 → 周二 10:00 都不是周三
        let start = date(2026, 8, 17, 20, 0, calendar: calendar)
        let end = date(2026, 8, 18, 10, 0, calendar: calendar)
        let segments = ActiveSchedule.activeSegments(schedule, from: start, to: end, calendar: calendar)
        XCTAssertTrue(segments.isEmpty)
    }

    func testAlwaysOnActiveEveryDayAndWholeWindow() {
        XCTAssertTrue(ActiveSchedule.isActive(
            .alwaysOn, at: date(2026, 8, 17, 0, calendar: calendar), calendar: calendar
        ))
        let start = date(2026, 8, 17, 0, calendar: calendar)
        let end = date(2026, 8, 18, 0, calendar: calendar)
        let segments = ActiveSchedule.activeSegments(.alwaysOn, from: start, to: end, calendar: calendar)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].0, start)
        XCTAssertEqual(segments[0].1, end)
    }
}
