import XCTest
@testable import LoopCue

final class UIFormattersTests: XCTestCase {
    func testCountdownSubtractsElapsedAndClampsAtZero() {
        let snapshotNow = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 1_000 + 65)

        XCTAssertEqual(
            UIFormatters.countdown(.minutes(2), since: snapshotNow, now: later),
            "55 秒"
        )
        // 已过期 → 0 秒，不出现负值。
        XCTAssertEqual(
            UIFormatters.countdown(.seconds(30), since: snapshotNow, now: later),
            "0 秒"
        )
    }
}
