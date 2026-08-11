import Foundation
import SwiftUI

/// 把 Engine 发布的不可变快照转换为 SwiftUI 可观察状态（技术方案 14.1）。
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: AppSnapshot?
    /// nil = 尚未确定；false = 通知权限未开启
    @Published private(set) var notificationAllowed: Bool?
    /// 具体授权状态描述，用于诊断
    @Published private(set) var notificationStatusDetail: String?
    private var task: Task<Void, Never>?

    init(engine: ReminderEngine) {
        task = Task { [weak self] in
            for await snapshot in engine.snapshots {
                self?.snapshot = snapshot
            }
        }
    }

    func set(_ snapshot: AppSnapshot) {
        self.snapshot = snapshot
    }

    func setNotificationAllowed(_ allowed: Bool?) {
        self.notificationAllowed = allowed
    }

    func setNotificationStatusDetail(_ detail: String?) {
        self.notificationStatusDetail = detail
    }
}
