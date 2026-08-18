import Foundation

/// 生效日与生效时段（PRD F-01/F-03 / 技术方案 8.7）。
///
/// - `weekdayMask`：ISO 工作日位集合（1 = 周一 … 7 = 周日）。
/// - `startMinute` / `endMinute`：当天生效时段，单位为「当天第几分钟」（0…1440）。
///   支持跨日之前的单个时段；MVP 校验 `start < end`，不支持跨午夜。
struct ActiveSchedule: Equatable, Sendable, Codable, Hashable {
    var weekdayMask: Set<Int>
    var startMinute: Int
    var endMinute: Int

    /// 默认：每天、全天生效。
    static let alwaysOn = ActiveSchedule(
        weekdayMask: Set(1...7),
        startMinute: 0,
        endMinute: 1440
    )

    /// 某时刻是否在生效时段内（工作日 + 时段）。
    static func isActive(_ schedule: ActiveSchedule, at date: Date, calendar: Calendar) -> Bool {
        guard schedule.weekdayMask.contains(isoWeekday(date, calendar: calendar)) else {
            return false
        }
        let minute = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        return minute >= schedule.startMinute && minute < schedule.endMinute
    }

    /// 计算 `[windowStart, windowEnd]` 内处于生效时段的累计时长。
    ///
    /// 按天切分：每个工作日只取 [startMinute, endMinute) 与窗口的交集。
    static func activeSegments(
        _ schedule: ActiveSchedule,
        from windowStart: Date,
        to windowEnd: Date,
        calendar: Calendar
    ) -> [(Date, Date)] {
        guard windowEnd > windowStart else { return [] }
        var segments: [(Date, Date)] = []
        var day = calendar.startOfDay(for: windowStart)
        let lastDay = calendar.startOfDay(for: windowEnd)

        while day <= lastDay {
            let weekday = isoWeekday(day, calendar: calendar)
            if schedule.weekdayMask.contains(weekday) {
                let dayStart = day.addingTimeInterval(TimeInterval(schedule.startMinute * 60))
                let dayEnd = day.addingTimeInterval(TimeInterval(schedule.endMinute * 60))
                let segmentStart = max(windowStart, dayStart)
                let segmentEnd = min(windowEnd, dayEnd)
                if segmentEnd > segmentStart {
                    segments.append((segmentStart, segmentEnd))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return segments
    }

    /// 把 Gregorian 的 weekday（1 = 周日）转成 ISO（1 = 周一）。
    static func isoWeekday(_ date: Date, calendar: Calendar) -> Int {
        let gregorian = calendar.component(.weekday, from: date)
        return (gregorian + 5) % 7 + 1
    }
}
