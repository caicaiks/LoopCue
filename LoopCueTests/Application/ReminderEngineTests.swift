import XCTest
@testable import LoopCue

final class ReminderEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func makeConfig(name: String = "测试", intervalMinutes: Int64 = 5) -> ReminderConfig {
        ReminderConfig(
            name: name,
            interval: .minutes(intervalMinutes),
            escalationDelay: .minutes(2)
        )
    }

    func testCreateStartsCountingCycle() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)

        try await engine.handle(.create(makeConfig()), now: t0)
        let snapshot = try await engine.start(now: t0)

        XCTAssertEqual(snapshot.reminders.count, 1)
        XCTAssertEqual(snapshot.reminders.first?.phase, .counting)
        XCTAssertNotNil(snapshot.reminders.first?.cycleID)
    }

    func testDebugTimeScaleFiresAfterScaledInterval() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store, timeScale: 10)
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)

        // 真实 30 秒 × 10 倍速 = 5 分钟 → 弱提醒
        try await engine.reconcile(now: t0.addingTimeInterval(30))
        let snapshot = try await engine.start(now: t0.addingTimeInterval(30))
        XCTAssertEqual(snapshot.reminders.first?.phase, .weakPending)
    }

    func testDefaultTimeScaleRequiresFullInterval() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)

        // 默认 1 倍速：30 秒不足，300 秒刚好触发
        try await engine.reconcile(now: t0.addingTimeInterval(30))
        let early = try await engine.start(now: t0.addingTimeInterval(30))
        XCTAssertEqual(early.reminders.first?.phase, .counting)

        try await engine.reconcile(now: t0.addingTimeInterval(300))
        let late = try await engine.start(now: t0.addingTimeInterval(300))
        XCTAssertEqual(late.reminders.first?.phase, .weakPending)
    }

    func testReconcileAdvancesToWeakPendingAndQueuesNotification() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)

        try await engine.reconcile(now: t0.addingTimeInterval(5 * 60))

        let snapshot = try await engine.start(now: t0.addingTimeInterval(5 * 60))
        XCTAssertEqual(snapshot.reminders.first?.phase, .weakPending)

        let pending = try store.loadPendingEffects()
        XCTAssertTrue(pending.contains { stored in
            if case .sendWeakNotification = stored.effect { return true }
            return false
        })
        let events = try store.loadEvents(reminderID: config.id)
        XCTAssertEqual(events.map(\.type), [.weakTriggered])
    }

    func testCompleteResetsCycleAndRecordsEvent() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)
        try await engine.reconcile(now: t0.addingTimeInterval(5 * 60))

        let before = try await engine.start(now: t0.addingTimeInterval(5 * 60))
        let oldCycleID = try XCTUnwrap(before.reminders.first?.cycleID)

        try await engine.handle(
            .complete(reminderID: config.id, cycleID: oldCycleID),
            now: t0.addingTimeInterval(5 * 60)
        )

        let after = try await engine.start(now: t0.addingTimeInterval(5 * 60))
        XCTAssertEqual(after.reminders.first?.phase, .counting)
        XCTAssertNotEqual(after.reminders.first?.cycleID, oldCycleID)

        let events = try store.loadEvents(reminderID: config.id)
        XCTAssertEqual(events.map(\.type), [.weakTriggered, .completed])
    }

    func testStaleCycleIDIsIgnored() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)
        let snapshot = try await engine.start(now: t0)
        let currentCycleID = try XCTUnwrap(snapshot.reminders.first?.cycleID)

        // 使用错误的 cycleID → 无副作用
        try await engine.handle(
            .complete(reminderID: config.id, cycleID: UUID()),
            now: t0
        )

        let after = try await engine.start(now: t0)
        XCTAssertEqual(after.reminders.first?.cycleID, currentCycleID)
        XCTAssertTrue(try store.loadEvents(reminderID: config.id).isEmpty)
    }

    func testRestartRecoveryRestoresPendingState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("LoopCue.sqlite")

        let store1 = try CoreDataReminderStore(persistentStoreURL: url)
        let engine1 = ReminderEngine(store: store1)
        let config = makeConfig(name: "重启恢复")
        try await engine1.handle(.create(config), now: t0)
        try await engine1.reconcile(now: t0.addingTimeInterval(5 * 60))

        // 模拟重启：新 store + 新 Engine 读取同一文件
        let store2 = try CoreDataReminderStore(persistentStoreURL: url)
        let engine2 = ReminderEngine(store: store2)
        let snapshot = try await engine2.start(now: t0.addingTimeInterval(5 * 60))

        XCTAssertEqual(snapshot.reminders.first?.phase, .weakPending)
        XCTAssertEqual(snapshot.reminders.first?.config.name, "重启恢复")
    }
}
