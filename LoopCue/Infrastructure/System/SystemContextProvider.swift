import Foundation

/// 提供当前系统上下文（技术方案 12.2）。Engine 通过它读取门控所需状态。
protocol SystemContextProviding: Sendable {
    func currentContext(now: Date) -> SystemContext
}

/// 静态上下文：默认全量计时（未接入 Monitor 的测试或简化路径使用）。
struct StaticSystemContextProvider: SystemContextProviding {
    func currentContext(now: Date) -> SystemContext {
        SystemContext(now: now, idleDuration: .zero, lastInputAt: now)
    }
}

/// 应用级状态存储（当前只存全局暂停截止，技术方案 9.1 CDAppState 的最小实现）。
protocol AppStateStoring: Sendable {
    func globalPauseUntil() -> Date?
    func setGlobalPauseUntil(_ date: Date?)
}

/// 基于 UserDefaults 的应用状态存储。
final class UserDefaultsAppStateStore: AppStateStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "loopcue.globalPauseUntil"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func globalPauseUntil() -> Date? {
        defaults.object(forKey: key) as? Date
    }

    func setGlobalPauseUntil(_ date: Date?) {
        if let date {
            defaults.set(date, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
