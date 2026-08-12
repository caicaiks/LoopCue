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

    func testRuntimePersistenceRoundTrip() throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let config = makeConfig()
        let cycle = ReminderCycle(
            reminderID: config.id,
            policy: CyclePolicySnapshot(config: config),
            startedAt: Date()
        )
        let runtime = ReminderRuntimeState(pauseUntil: Date(timeIntervalSince1970: 5_000_000))
        try store.saveReminder(StoredReminder(config: config, cycle: cycle, runtime: runtime))

        let loaded = try store.loadReminders()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.runtime, runtime)
    }

    func testRuntimeDefaultsWhenNotExplicitlySet() throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let config = makeConfig()
        try store.saveReminder(StoredReminder(config: config, cycle: nil))

        let loaded = try store.loadReminders().first
        XCTAssertEqual(loaded?.runtime, ReminderRuntimeState())
        XCTAssertNil(loaded?.runtime.pauseUntil)
    }

    func testReminderConfigLegacyDecodeFallsBackToAlwaysOn() throws {
        // 旧格式 JSON（无 activeSchedule 字段）→ 回退为 .alwaysOn，整行可正常解码。
        let config = makeConfig(name: "旧数据")
        let encoder = JSONEncoder()
        let fullData = try encoder.encode(config)
        var object = try JSONSerialization.jsonObject(with: fullData) as! [String: Any]
        object.removeValue(forKey: "activeSchedule")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ReminderConfig.self, from: legacyData)
        XCTAssertEqual(decoded.name, config.name)
        XCTAssertEqual(decoded.activeSchedule, .alwaysOn)
    }

    func testReminderConfigLegacyDecodeFallsBackToAllScreens() throws {
        // 旧格式 JSON（无 displayScope 字段）→ 回退为 .all（PRD 默认覆盖所有显示器）。
        let config = makeConfig(name: "旧数据")
        let encoder = JSONEncoder()
        let fullData = try encoder.encode(config)
        var object = try JSONSerialization.jsonObject(with: fullData) as! [String: Any]
        object.removeValue(forKey: "displayScope")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ReminderConfig.self, from: legacyData)
        XCTAssertEqual(decoded.name, config.name)
        XCTAssertEqual(decoded.displayScope, .all)
    }

    func testLegacyCycleWithoutDisplayScopeDecodes() throws {
        // 复现升级崩溃路径：旧 cycleData 中 policy 缺少 displayScope 字段时，
        // ReminderCycle 整体必须可解码，且回退为 .all（PRD 默认覆盖所有显示器）。
        let config = makeConfig(name: "旧数据")
        let cycle = ReminderCycle(
            reminderID: config.id,
            policy: CyclePolicySnapshot(config: config),
            startedAt: Date()
        )
        let encoder = JSONEncoder()
        let fullData = try encoder.encode(cycle)
        var object = try JSONSerialization.jsonObject(with: fullData) as! [String: Any]
        guard var policy = object["policy"] as? [String: Any] else {
            XCTFail("policy 字段缺失")
            return
        }
        policy.removeValue(forKey: "displayScope")
        object["policy"] = policy
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ReminderCycle.self, from: legacyData)
        XCTAssertEqual(decoded.policy.displayScope, .all)
        XCTAssertEqual(decoded.policy.interval, cycle.policy.interval)
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
