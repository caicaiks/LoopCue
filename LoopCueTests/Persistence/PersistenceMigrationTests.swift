import XCTest
@testable import LoopCue

/// M2 数据模型 v1 冻结与迁移基线（技术方案 9.2 / 19.3）：
/// - 存储元数据记录 schema 版本；
/// - 旧格式（缺新字段）数据重启后可读且字段回退默认值；
/// - 单条损坏数据被隔离，不影响其余提醒加载。
final class PersistenceMigrationTests: XCTestCase {
    private func makeConfig(name: String = "起身活动") -> ReminderConfig {
        ReminderConfig(
            name: name,
            interval: .minutes(30),
            escalationDelay: .minutes(30)
        )
    }

    /// 临时 SQLite 目录 + 清理。
    private func makeTempStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("LoopCue.sqlite")
    }

    // MARK: - Schema 版本元数据

    func testStoreRecordsSchemaVersion() throws {
        let url = try makeTempStoreURL()
        // 内层作用域：创建即写入元数据，随后释放连接。
        do {
            _ = try CoreDataReminderStore(persistentStoreURL: url)
        }

        // 读取存储元数据，确认写入了当前 schema 版本。
        let container = NSPersistentContainer(
            name: "LoopCueFixture",
            managedObjectModel: CoreDataReminderStore.makeModel()
        )
        container.persistentStoreDescriptions.first?.url = url
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError { throw loadError }
        let metadata = container.persistentStoreCoordinator.persistentStores.first?.metadata ?? [:]
        XCTAssertEqual(metadata["LoopCueSchemaVersion"] as? Int, CoreDataReminderStore.schemaVersion)
    }

    func testRestartKeepsSchemaCompatible() throws {
        // v1 数据重启后仍可正常读取（同版本无迁移）。
        let url = try makeTempStoreURL()
        let config = makeConfig(name: "重启兼容")
        try CoreDataReminderStore(persistentStoreURL: url)
            .saveReminder(StoredReminder(config: config, cycle: nil))

        let restored = try CoreDataReminderStore(persistentStoreURL: url).loadReminders()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.config.name, "重启兼容")
    }

    // MARK: - 旧格式数据迁移兼容（缺 displayScope / activeSchedule）

    func testLegacyConfigMissingFieldsSurvivesRestart() throws {
        // 构造「旧版本」configData：去掉 displayScope / activeSchedule 两个后加字段，
        // 落盘后重启读取，应回退为 .all / .alwaysOn（PRD 默认）。
        let url = try makeTempStoreURL()
        let config = makeConfig(name: "旧数据重启")
        let encoder = JSONEncoder()
        let fullData = try encoder.encode(config)
        var object = try JSONSerialization.jsonObject(with: fullData) as! [String: Any]
        object.removeValue(forKey: "displayScope")
        object.removeValue(forKey: "activeSchedule")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        // 直接用 Core Data 写入一条旧格式行（绕过新 store 的编码路径）。
        try writeLegacyReminderRow(
            to: url,
            id: config.id,
            name: "旧数据重启",
            configData: legacyData
        )

        let restored = try CoreDataReminderStore(persistentStoreURL: url).loadReminders()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.config.name, "旧数据重启")
        XCTAssertEqual(restored.first?.config.displayScope, .all)
        XCTAssertEqual(restored.first?.config.activeSchedule, .alwaysOn)
    }

    // MARK: - 单条损坏数据隔离

    func testCorruptRowIsIsolatedAndOthersLoad() throws {
        let url = try makeTempStoreURL()
        let goodConfig = makeConfig(name: "正常提醒")
        // 内层作用域：写完即释放第一个 store 的连接，避免与 fixture 容器
        // 同时持锁同一 SQLite 文件。
        do {
            let store = try CoreDataReminderStore(persistentStoreURL: url)
            try store.saveReminder(StoredReminder(config: goodConfig, cycle: nil))
        }

        // 注入一条损坏行（configData 非法 JSON，无法解码）。
        try writeLegacyReminderRow(
            to: url,
            id: UUID(),
            name: "损坏行",
            configData: Data("not-json".utf8)
        )

        // 重启后：损坏行被跳过，正常提醒仍可加载（技术方案 13.2 隔离单条）。
        let restored = try CoreDataReminderStore(persistentStoreURL: url).loadReminders()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.config.name, "正常提醒")
    }

    // MARK: - Helpers

    /// 直接用生产数据模型（CoreDataReminderStore.makeModel）写入一行指定
    /// configData 的提醒，用于构造「旧版本 / 损坏」的持久化数据
    /// （不经过新 store 的编码路径）。
    private func writeLegacyReminderRow(
        to url: URL,
        id: UUID,
        name: String,
        configData: Data
    ) throws {
        let container = NSPersistentContainer(
            name: "LoopCueFixture",
            managedObjectModel: CoreDataReminderStore.makeModel()
        )
        container.persistentStoreDescriptions.first?.url = url
        container.persistentStoreDescriptions.first?.type = NSSQLiteStoreType

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError { throw loadError }

        let context = container.newBackgroundContext()
        try context.performAndWait {
            let entity = NSEntityDescription.entity(
                forEntityName: "ManagedReminder",
                in: context
            )!
            let row = NSManagedObject(entity: entity, insertInto: context)
            row.setValue(id, forKey: "id")
            row.setValue(name, forKey: "name")
            row.setValue(configData, forKey: "configData")
            row.setValue(nil, forKey: "cycleData")
            row.setValue(nil, forKey: "runtimeData")
            row.setValue(false, forKey: "isEnabled")
            try context.save()
        }
    }
}
