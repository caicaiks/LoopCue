import XCTest
@testable import LoopCue

final class CoreDataReminderStoreTests: XCTestCase {
    private func makeConfig(name: String = "起身活动") -> ReminderConfig {
        ReminderConfig(
            name: name,
            interval: .minutes(30),
            escalationDelay: .minutes(30)
        )
    }

    func testSaveAndLoadReminderWithCycle() throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let config = makeConfig()
        let cycle = ReminderCycle(
            reminderID: config.id,
            policy: CyclePolicySnapshot(config: config),
            startedAt: Date()
        )
        try store.saveReminder(StoredReminder(config: config, cycle: cycle))

        let loaded = try store.loadReminders()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.config, config)
        XCTAssertEqual(loaded.first?.cycle, cycle)
    }

    func testSaveSameReminderUpdatesInPlace() throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let config = makeConfig()
        try store.saveReminder(StoredReminder(config: config, cycle: nil))

        var changed = config
        changed.name = "喝水"
        try store.saveReminder(StoredReminder(config: changed, cycle: nil))

        let loaded = try store.loadReminders()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.config.name, "喝水")
    }

    func testAppendAndLoadEvents() throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let reminderID = UUID()
        let cycleID = UUID()
        let event = ReminderEvent(
            reminderID: reminderID,
            cycleID: cycleID,
            type: .completed,
            occurredAt: Date()
        )
        try store.appendEvent(event)

        let loaded = try store.loadEvents(reminderID: reminderID)
        XCTAssertEqual(loaded, [event])
    }

    func testEffectsPendingAndMarkDone() throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let effect = StoredEffect(
            id: UUID(),
            effect: .presentStrongOverlay(reminderID: UUID(), cycleID: UUID()),
            dedupeKey: "strong:x",
            isDone: false
        )
        try store.appendEffect(effect)
        XCTAssertEqual(try store.loadPendingEffects(), [effect])

        try store.markEffectDone(id: effect.id)
        XCTAssertTrue(try store.loadPendingEffects().isEmpty)
    }

    func testDeleteReminder() throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let config = makeConfig()
        try store.saveReminder(StoredReminder(config: config, cycle: nil))

        try store.deleteReminder(id: config.id)
        XCTAssertTrue(try store.loadReminders().isEmpty)
    }

    func testRestartRecoveryWithSQLite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("LoopCue.sqlite")

        let config = makeConfig(name: "恢复测试")
        let cycle = ReminderCycle(
            reminderID: config.id,
            policy: CyclePolicySnapshot(config: config),
            startedAt: Date()
        )
        try CoreDataReminderStore(persistentStoreURL: url)
            .saveReminder(StoredReminder(config: config, cycle: cycle))

        // 模拟重启：用同一 SQLite 文件新建 store
        let restored = try CoreDataReminderStore(persistentStoreURL: url).loadReminders()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.config.name, "恢复测试")
        XCTAssertEqual(restored.first?.cycle, cycle)
    }
}
