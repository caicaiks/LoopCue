import XCTest
@testable import LoopCue

final class ReminderTemplateTests: XCTestCase {
    func testAllTemplatesPassValidation() {
        for template in ReminderTemplate.allCases {
            let config = template.makeConfig()
            switch ReminderValidation.validate(config) {
            case .success:
                break
            case .failure(let error):
                XCTFail("模板 \(template.title) 校验失败：\(error)")
            }
        }
    }

    func testStandUpTemplateDefaults() {
        let config = ReminderTemplate.standUp.makeConfig()
        XCTAssertEqual(config.name, "起身活动")
        XCTAssertEqual(config.icon, .standUp)
        XCTAssertEqual(config.interval, .minutes(30))
        XCTAssertEqual(config.escalationDelay, .minutes(30))
        XCTAssertEqual(config.snoozeDuration, .minutes(10))
        XCTAssertEqual(config.maxSnoozeCount, 2)
        XCTAssertEqual(config.awayPolicy, .complete(threshold: .minutes(3)))
    }

    func testWaterTemplatePausesOnAway() {
        let config = ReminderTemplate.water.makeConfig()
        XCTAssertEqual(config.interval, .minutes(45))
        XCTAssertEqual(config.escalationDelay, .minutes(15))
        if case .pause(let threshold) = config.awayPolicy {
            XCTAssertEqual(threshold, .minutes(5))
        } else {
            XCTFail("喝水模板应为暂停策略")
        }
    }

    func testFarGazeTemplateDefaults() {
        let config = ReminderTemplate.farGaze.makeConfig()
        XCTAssertEqual(config.interval, .minutes(20))
        XCTAssertEqual(config.escalationDelay, .minutes(5))
        XCTAssertEqual(config.maxSnoozeCount, 1)
    }

    func testCustomTemplateHasNoEscalation() {
        let config = ReminderTemplate.custom.makeConfig()
        XCTAssertNil(config.escalationDelay)
        XCTAssertEqual(config.interval, .minutes(60))
    }
}
