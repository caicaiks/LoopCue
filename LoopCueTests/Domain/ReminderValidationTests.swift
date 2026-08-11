import XCTest
@testable import LoopCue

final class ReminderValidationTests: XCTestCase {
    func testReminderConfigKeepsFields() {
        let config = ReminderConfig(name: "起身活动", intervalSeconds: 1800)
        XCTAssertEqual(config.name, "起身活动")
        XCTAssertEqual(config.intervalSeconds, 1800)
    }

    func testIntentCarriesCycleIdentity() {
        let reminderID = UUID()
        let cycleID = UUID()
        let intent = ReminderIntent.complete(reminderID: reminderID, cycleID: cycleID)
        XCTAssertEqual(intent, .complete(reminderID: reminderID, cycleID: cycleID))
    }
}

