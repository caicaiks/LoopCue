import XCTest
@testable import LoopCue

@MainActor
final class AppSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "loopcue.settings.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsFallback() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.defaultDisplayScope, .all)
        XCTAssertEqual(store.defaultAwayMinutes, 5)
        XCTAssertEqual(store.defaultAwayPolicy, .pause(threshold: .minutes(5)))
    }

    func testPersistedValuesRoundTrip() {
        let store = AppSettingsStore(defaults: defaults)
        store.defaultDisplayScope = .current
        store.defaultAwayMinutes = 10

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.defaultDisplayScope, .current)
        XCTAssertEqual(reloaded.defaultAwayMinutes, 10)
        XCTAssertEqual(reloaded.defaultAwayPolicy, .pause(threshold: .minutes(10)))
    }

    func testUnknownAwayMinutesFallsBackToFive() {
        defaults.set(42, forKey: "loopcue.settings.defaultAwayMinutes")
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.defaultAwayMinutes, 5)
    }

    func testOnboardingFlagDefaultsFalseAndPersists() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(store.hasCompletedOnboarding)

        store.hasCompletedOnboarding = true
        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }
}
