import XCTest
@testable import LoopCue

final class ReminderValidationTests: XCTestCase {
    private func makeValidConfig() -> ReminderConfig {
        ReminderConfig(
            name: "起身活动",
            message: "该起来走一走了",
            completionLabel: "已起身",
            interval: .minutes(30),
            escalationDelay: .minutes(30),
            snoozeDuration: .minutes(10),
            maxSnoozeCount: 2,
            awayPolicy: .complete(threshold: .minutes(3))
        )
    }

    private func expectValidationPass(_ config: ReminderConfig) {
        switch ReminderValidation.validate(config) {
        case .success:
            break
        case .failure(let error):
            XCTFail("期望校验通过，但失败：\(error)")
        }
    }

    private func expectValidationFailure(
        _ config: ReminderConfig,
        _ expected: ReminderValidationError
    ) {
        switch ReminderValidation.validate(config) {
        case .success:
            XCTFail("期望校验失败 \(expected)，但校验通过")
        case .failure(let error):
            XCTAssertEqual(error, expected)
        }
    }

    func testValidConfigPasses() {
        expectValidationPass(makeValidConfig())
    }

    func testScheduleValidation() {
        var config = makeValidConfig()
        config.activeSchedule = .alwaysOn
        expectValidationPass(config)

        config.activeSchedule = ActiveSchedule(weekdayMask: [1], startMinute: -1, endMinute: 1440)
        expectValidationFailure(config, .scheduleStartMinuteOutOfRange)

        config.activeSchedule = ActiveSchedule(weekdayMask: [1], startMinute: 0, endMinute: 0)
        expectValidationFailure(config, .scheduleEndMinuteOutOfRange)

        config.activeSchedule = ActiveSchedule(weekdayMask: [1], startMinute: 1440, endMinute: 1440)
        expectValidationFailure(config, .scheduleStartMinuteOutOfRange)

        config.activeSchedule = ActiveSchedule(weekdayMask: [1], startMinute: 600, endMinute: 600)
        expectValidationFailure(config, .scheduleCrossesMidnight)

        config.activeSchedule = ActiveSchedule(weekdayMask: [1], startMinute: 600, endMinute: 500)
        expectValidationFailure(config, .scheduleCrossesMidnight)

        config.activeSchedule = ActiveSchedule(weekdayMask: [], startMinute: 0, endMinute: 1440)
        expectValidationFailure(config, .scheduleWeekdayEmpty)
    }

    func testNameLengthBoundaries() {
        var config = makeValidConfig()
        config.name = ""
        expectValidationFailure(config, .nameTooShort)

        config.name = String(repeating: "测", count: 21)
        expectValidationFailure(config, .nameTooLong)

        config.name = String(repeating: "测", count: 20)
        expectValidationPass(config)
    }

    func testCompletionLabelLength() {
        var config = makeValidConfig()
        config.completionLabel = ""
        expectValidationFailure(config, .completionLabelTooShort)

        config.completionLabel = String(repeating: "完", count: 9)
        expectValidationFailure(config, .completionLabelTooLong)
    }

    func testIntervalBoundaries() {
        var config = makeValidConfig()
        config.interval = .minutes(4)
        expectValidationFailure(config, .intervalOutOfRange)

        config.interval = .hours(25)
        expectValidationFailure(config, .intervalOutOfRange)

        config.interval = .minutes(5)
        expectValidationPass(config)
    }

    func testEscalationDelayOptionalAndBoundaries() {
        var config = makeValidConfig()
        config.escalationDelay = nil
        expectValidationPass(config)

        config.escalationDelay = .seconds(30)
        expectValidationFailure(config, .escalationDelayOutOfRange)
    }

    func testSnoozeCountBoundaries() {
        var config = makeValidConfig()
        config.maxSnoozeCount = -1
        expectValidationFailure(config, .snoozeCountOutOfRange)

        config.maxSnoozeCount = 11
        expectValidationFailure(config, .snoozeCountOutOfRange)

        config.maxSnoozeCount = 10
        expectValidationPass(config)
    }

    func testReminderConfigKeepsFields() {
        let config = makeValidConfig()
        XCTAssertEqual(config.name, "起身活动")
        XCTAssertEqual(config.interval, .minutes(30))
        XCTAssertEqual(config.completionLabel, "已起身")
    }

    func testIntentCarriesCycleIdentity() {
        let reminderID = UUID()
        let cycleID = UUID()
        let intent = ReminderIntent.complete(reminderID: reminderID, cycleID: cycleID)
        XCTAssertEqual(intent, .complete(reminderID: reminderID, cycleID: cycleID))
    }
}

