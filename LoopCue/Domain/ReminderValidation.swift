import Foundation

/// 配置校验错误（PRD F-01 / 技术方案 6.1）。
enum ReminderValidationError: Error, Equatable {
    case nameTooShort
    case nameTooLong
    case messageTooLong
    case completionLabelTooShort
    case completionLabelTooLong
    case intervalOutOfRange
    case escalationDelayOutOfRange
    case scheduleStartMinuteOutOfRange
    case scheduleEndMinuteOutOfRange
    case scheduleCrossesMidnight
    case scheduleWeekdayEmpty
    case snoozeDurationOutOfRange
    case snoozeCountOutOfRange
}

/// 配置校验规则，与 PRD 一致，在 Domain 层统一执行。
enum ReminderValidation {
    private static let nameMin = 1
    private static let nameMax = 20
    private static let messageMax = 80
    private static let completionLabelMin = 1
    private static let completionLabelMax = 8
    private static let intervalMin: Duration = .minutes(5)
    private static let intervalMax: Duration = .hours(24)
    private static let escalationDelayMin: Duration = .minutes(1)
    private static let escalationDelayMax: Duration = .hours(24)
    private static let snoozeDurationMin: Duration = .minutes(1)
    private static let snoozeDurationMax: Duration = .hours(24)
    private static let snoozeCountMax = 10

    static func validate(_ config: ReminderConfig) -> Result<Void, ReminderValidationError> {
        let nameCount = config.name.count
        if nameCount < nameMin { return .failure(.nameTooShort) }
        if nameCount > nameMax { return .failure(.nameTooLong) }
        if config.message.count > messageMax { return .failure(.messageTooLong) }

        let labelCount = config.completionLabel.count
        if labelCount < completionLabelMin { return .failure(.completionLabelTooShort) }
        if labelCount > completionLabelMax { return .failure(.completionLabelTooLong) }

        guard config.interval >= intervalMin, config.interval <= intervalMax else {
            return .failure(.intervalOutOfRange)
        }
        if let delay = config.escalationDelay {
            guard delay >= escalationDelayMin, delay <= escalationDelayMax else {
                return .failure(.escalationDelayOutOfRange)
            }
        }
        let schedule = config.activeSchedule
        guard schedule.startMinute >= 0, schedule.startMinute < 1440 else {
            return .failure(.scheduleStartMinuteOutOfRange)
        }
        guard schedule.endMinute > 0, schedule.endMinute <= 1440 else {
            return .failure(.scheduleEndMinuteOutOfRange)
        }
        guard schedule.startMinute < schedule.endMinute else {
            return .failure(.scheduleCrossesMidnight)
        }
        guard !schedule.weekdayMask.isEmpty else { return .failure(.scheduleWeekdayEmpty) }
        guard config.snoozeDuration >= snoozeDurationMin, config.snoozeDuration <= snoozeDurationMax else {
            return .failure(.snoozeDurationOutOfRange)
        }
        guard config.maxSnoozeCount >= 0, config.maxSnoozeCount <= snoozeCountMax else {
            return .failure(.snoozeCountOutOfRange)
        }
        return .success(())
    }
}
