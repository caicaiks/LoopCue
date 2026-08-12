import Foundation
import SwiftUI

/// 应用偏好（技术方案 9.1：非关键偏好放 UserDefaults）。
///
/// 当前包含新建提醒的默认值：覆盖显示器范围、离开阈值。
/// 编辑已有提醒不受这些默认值影响；仅「新建」时作为初始值。
@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var defaultDisplayScope: DisplayScope {
        didSet { defaults.set(defaultDisplayScope.rawValue, forKey: Self.displayScopeKey) }
    }

    /// 默认离开阈值（分钟）。策略固定为「暂停计时」，
    /// 起身模板的「视为完成」仍由模板自身决定。
    @Published var defaultAwayMinutes: Int {
        didSet { defaults.set(defaultAwayMinutes, forKey: Self.awayMinutesKey) }
    }

    /// 新建提醒的默认离开策略。
    var defaultAwayPolicy: AwayPolicy {
        .pause(threshold: .minutes(Int64(defaultAwayMinutes)))
    }

    private static let displayScopeKey = "loopcue.settings.defaultDisplayScope"
    private static let awayMinutesKey = "loopcue.settings.defaultAwayMinutes"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.displayScopeKey),
           let scope = DisplayScope(rawValue: raw) {
            defaultDisplayScope = scope
        } else {
            defaultDisplayScope = .all
        }
        if let minutes = defaults.object(forKey: Self.awayMinutesKey) as? Int {
            defaultAwayMinutes = Self.sanitize(minutes)
        } else {
            defaultAwayMinutes = 5
        }
    }

    private static func sanitize(_ minutes: Int) -> Int {
        Self.awayOptions.contains(minutes) ? minutes : 5
    }

    /// 设置页可选的离开阈值（分钟）。
    static let awayOptions = [1, 3, 5, 10, 15, 30, 60]
}
