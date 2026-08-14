import CoreData
import Foundation
import os

/// 基于 Core Data 的本地仓库。
///
/// M0-C 采用编程式 NSManagedObjectModel，领域值类型以 Codable JSON
/// 存于实体属性中。实体按 Reminder / Event / Effect 拆分，便于后续
/// 迁移与查询；无需额外的 .xcdatamodeld 文件即可在 CLI 中构建与测试。
final class CoreDataReminderStore: ReminderStore, @unchecked Sendable {
    private let container: NSPersistentContainer
    /// 子系统日志（技术方案 17）：只记录迁移/事务/checkpoint 错误，
    /// 不记录提醒正文、完成文案或用户输入。
    private static let logger = Logger(
        subsystem: "com.loopcue.LoopCue",
        category: "persistence"
    )
    /// 数据模型 v1 冻结标记（技术方案 9.2 / M2 数据模型冻结）：
    /// 写入持久化存储元数据，供未来迁移判断与诊断。
    static let schemaVersion = 1
    private static let schemaVersionKey = "LoopCueSchemaVersion"

    init(inMemory: Bool = false, persistentStoreURL: URL? = nil) throws {
        container = NSPersistentContainer(
            name: "LoopCue",
            managedObjectModel: Self.makeModel()
        )
        if let url = persistentStoreURL {
            container.persistentStoreDescriptions.first?.url = url
        } else if inMemory {
            container.persistentStoreDescriptions.first?.url =
                URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions.first?.type = NSInMemoryStoreType
        } else {
            container.persistentStoreDescriptions.first?.url =
                try Self.defaultStoreURL()
        }

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            Self.logger.error("打开持久化存储失败: \(loadError, privacy: .public)")
            throw loadError
        }
        // 加载成功后从 coordinator 取真实 store 记录 schema 版本。
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            Self.recordSchemaVersion(in: store)
        }
    }

    /// 在存储元数据中记录/校验数据模型版本：低于当前版本视为迁移
    /// （v1 无历史版本，仅记录）；高于当前版本时告警不覆盖数据。
    private static func recordSchemaVersion(in store: NSPersistentStore) {
        var metadata = store.metadata ?? [:]
        let existing = metadata[schemaVersionKey] as? Int
        if let existing {
            if existing < schemaVersion {
                Self.logger.notice("数据模型迁移: v\(existing) → v\(schemaVersion)")
            } else if existing > schemaVersion {
                Self.logger.error(
                    "存储数据版本 v\(existing) 高于当前支持 v\(schemaVersion)，请升级应用；不修改原数据"
                )
                return
            } else {
                return
            }
        }
        metadata[schemaVersionKey] = schemaVersion
        store.metadata = metadata
    }

    // MARK: - ReminderStore

    func loadReminders() throws -> [StoredReminder] {
        try perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ManagedReminder")
            let objects = try context.fetch(request)
            // 隔离单条坏数据：decode 失败只记录并跳过该条，其余提醒继续工作
            // （技术方案 13.2「数据模型字段非法 → 隔离单条并记录错误」）。
            return objects.compactMap { object in
                do {
                    return try Self.decode(object)
                } catch {
                    Self.logger.error("跳过损坏的提醒行: \(error, privacy: .public)")
                    return nil
                }
            }
        }
    }

    func saveReminder(_ reminder: StoredReminder) throws {
        try perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ManagedReminder")
            request.predicate = NSPredicate(format: "id == %@", reminder.config.id as CVarArg)
            let existing = try context.fetch(request).first
            let object = existing ?? NSEntityDescription.insertNewObject(
                forEntityName: "ManagedReminder",
                into: context
            )
            let configData = try JSONEncoder().encode(reminder.config)
            let cycleData = try reminder.cycle.map { try JSONEncoder().encode($0) }
            let runtimeData = try JSONEncoder().encode(reminder.runtime)
            object.setValue(reminder.config.id, forKey: "id")
            object.setValue(reminder.config.name, forKey: "name")
            object.setValue(configData, forKey: "configData")
            object.setValue(cycleData, forKey: "cycleData")
            object.setValue(runtimeData, forKey: "runtimeData")
            object.setValue(reminder.config.isEnabled, forKey: "isEnabled")
        }
    }

    func deleteReminder(id: UUID) throws {
        try perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ManagedReminder")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let objects = try context.fetch(request)
            for object in objects {
                context.delete(object)
            }
        }
    }

    func deleteReminderCascade(id: UUID) throws {
        try perform { context in
            // 1) 提醒本体（含当前 Cycle 快照）。
            let reminderRequest = NSFetchRequest<NSManagedObject>(entityName: "ManagedReminder")
            reminderRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            for object in try context.fetch(reminderRequest) {
                context.delete(object)
            }

            // 2) 事件。
            let eventRequest = NSFetchRequest<NSManagedObject>(entityName: "ManagedEvent")
            eventRequest.predicate = NSPredicate(format: "reminderID == %@", id as CVarArg)
            for object in try context.fetch(eventRequest) {
                context.delete(object)
            }

            // 3) 属于该提醒的 Outbox 效果（解码匹配 reminderID）。
            let effectRequest = NSFetchRequest<NSManagedObject>(entityName: "ManagedEffect")
            for object in try context.fetch(effectRequest) {
                guard let effect = try? Self.decodeEffect(object),
                      Self.reminderID(of: effect) == id
                else { continue }
                context.delete(object)
            }
        }
    }

    func appendEvent(_ event: ReminderEvent) throws {
        try perform { context in
            let object = NSEntityDescription.insertNewObject(
                forEntityName: "ManagedEvent",
                into: context
            )
            object.setValue(event.id, forKey: "id")
            object.setValue(event.reminderID, forKey: "reminderID")
            object.setValue(event.cycleID, forKey: "cycleID")
            object.setValue(event.type.rawValue, forKey: "type")
            object.setValue(event.occurredAt, forKey: "occurredAt")
        }
    }

    func loadEvents(reminderID: UUID) throws -> [ReminderEvent] {
        try perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ManagedEvent")
            request.predicate = NSPredicate(format: "reminderID == %@", reminderID as CVarArg)
            let objects = try context.fetch(request)
            return objects.compactMap { object -> ReminderEvent? in
                guard
                    let id = object.value(forKey: "id") as? UUID,
                    let reminderID = object.value(forKey: "reminderID") as? UUID,
                    let cycleID = object.value(forKey: "cycleID") as? UUID,
                    let raw = object.value(forKey: "type") as? String,
                    let type = ReminderEventType(rawValue: raw),
                    let occurredAt = object.value(forKey: "occurredAt") as? Date
                else { return nil }
                return ReminderEvent(
                    reminderID: reminderID,
                    cycleID: cycleID,
                    type: type,
                    occurredAt: occurredAt,
                    id: id
                )
            }
        }
    }

    func appendEffect(_ effect: StoredEffect) throws {
        try perform { context in
            let object = NSEntityDescription.insertNewObject(
                forEntityName: "ManagedEffect",
                into: context
            )
            let data = try JSONEncoder().encode(effect.effect)
            object.setValue(effect.id, forKey: "id")
            object.setValue(data, forKey: "effectData")
            object.setValue(effect.dedupeKey, forKey: "dedupeKey")
            object.setValue(effect.isDone, forKey: "isDone")
        }
    }

    func markEffectDone(id: UUID) throws {
        try perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ManagedEffect")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let objects = try context.fetch(request)
            for object in objects {
                object.setValue(true, forKey: "isDone")
            }
        }
    }

    func loadPendingEffects() throws -> [StoredEffect] {
        try perform { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "ManagedEffect")
            request.predicate = NSPredicate(format: "isDone == NO")
            let objects = try context.fetch(request)
            return try objects.map { object -> StoredEffect in
                guard
                    let id = object.value(forKey: "id") as? UUID,
                    object.value(forKey: "effectData") is Data,
                    let dedupeKey = object.value(forKey: "dedupeKey") as? String,
                    let isDone = object.value(forKey: "isDone") as? Bool
                else {
                    throw PersistenceError.corruptRow
                }
                let effect = try Self.decodeEffect(object)
                return StoredEffect(id: id, effect: effect, dedupeKey: dedupeKey, isDone: isDone)
            }
        }
    }

    func resetAll() throws {
        try perform { context in
            for entityName in ["ManagedReminder", "ManagedEvent", "ManagedEffect"] {
                let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                let objects = try context.fetch(request)
                for object in objects {
                    context.delete(object)
                }
            }
        }
    }

    func clearEventsAndEffects() throws {
        try perform { context in
            for entityName in ["ManagedEvent", "ManagedEffect"] {
                let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                let objects = try context.fetch(request)
                for object in objects {
                    context.delete(object)
                }
            }
        }
    }

    // MARK: - Helpers

    private func perform<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) throws -> T {
        let context = container.newBackgroundContext()
        var result: Result<T, Error>!
        context.performAndWait {
            do {
                let value = try block(context)
                if context.hasChanges {
                    try context.save()
                }
                result = .success(value)
            } catch {
                Self.logger.error("持久化事务失败: \(error, privacy: .public)")
                result = .failure(error)
            }
        }
        return try result.get()
    }

    private static func decode(_ object: NSManagedObject) throws -> StoredReminder? {
        guard
            let configData = object.value(forKey: "configData") as? Data
        else { return nil }
        let config = try JSONDecoder().decode(ReminderConfig.self, from: configData)
        let cycle: ReminderCycle?
        if let cycleData = object.value(forKey: "cycleData") as? Data {
            cycle = try JSONDecoder().decode(ReminderCycle.self, from: cycleData)
        } else {
            cycle = nil
        }
        let runtime: ReminderRuntimeState
        if let runtimeData = object.value(forKey: "runtimeData") as? Data {
            runtime = try JSONDecoder().decode(ReminderRuntimeState.self, from: runtimeData)
        } else {
            runtime = ReminderRuntimeState()
        }
        return StoredReminder(config: config, cycle: cycle, runtime: runtime)
    }

    private static func decodeEffect(_ object: NSManagedObject) throws -> ReminderEffect {
        guard let data = object.value(forKey: "effectData") as? Data else {
            throw PersistenceError.corruptRow
        }
        return try JSONDecoder().decode(ReminderEffect.self, from: data)
    }

    private static func reminderID(of effect: ReminderEffect) -> UUID? {
        switch effect {
        case .sendWeakNotification(let reminderID, _, _),
             .clearNotifications(let reminderID, _),
             .presentStrongOverlay(let reminderID, _),
             .dismissStrongOverlay(let reminderID, _):
            return reminderID
        }
    }

    private static func defaultStoreURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("LoopCue", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("LoopCue.sqlite")
    }

    // MARK: - Model

    /// 编程式数据模型（internal 供测试复用构造 fixture，避免模型漂移）。
    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let reminder = NSEntityDescription()
        reminder.name = "ManagedReminder"
        reminder.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("configData", .binaryDataAttributeType),
            attribute("cycleData", .binaryDataAttributeType, optional: true),
            attribute("runtimeData", .binaryDataAttributeType, optional: true),
            attribute("isEnabled", .booleanAttributeType),
        ]

        let event = NSEntityDescription()
        event.name = "ManagedEvent"
        event.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("reminderID", .UUIDAttributeType),
            attribute("cycleID", .UUIDAttributeType),
            attribute("type", .stringAttributeType),
            attribute("occurredAt", .dateAttributeType),
        ]

        let effect = NSEntityDescription()
        effect.name = "ManagedEffect"
        effect.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("effectData", .binaryDataAttributeType),
            attribute("dedupeKey", .stringAttributeType),
            attribute("isDone", .booleanAttributeType),
        ]

        model.entities = [reminder, event, effect]
        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}

enum PersistenceError: Error, Equatable {
    case corruptRow
}
