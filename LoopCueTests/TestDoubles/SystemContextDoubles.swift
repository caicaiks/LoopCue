import Foundation
@testable import LoopCue

/// 可控系统上下文（测试用）。
///
/// 默认 `lastInputAt = .distantFuture` 表示「始终在场」；需要模拟离开时
/// 显式设置 `lastInputAt = now - idle` 与 `idleDuration`。
final class FakeContextProvider: SystemContextProviding, @unchecked Sendable {
    var context: SystemContext

    init(context: SystemContext = SystemContext(
        now: Date(timeIntervalSince1970: 5_000_000),
        lastInputAt: .distantFuture
    )) {
        self.context = context
    }

    func currentContext(now: Date) -> SystemContext {
        var snapshot = context
        snapshot.now = now
        return snapshot
    }
}

/// 内存应用状态（测试用）。
final class InMemoryAppStateStore: AppStateStoring, @unchecked Sendable {
    private var value: Date?

    func globalPauseUntil() -> Date? { value }
    func setGlobalPauseUntil(_ date: Date?) { value = date }
}

/// 固定 UTC Gregorian 日历，保证日期可预测。
func fixedCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

/// 用固定日历构造日期。
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, calendar: Calendar) -> Date {
    calendar.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    )!
}
