import Foundation
import SwiftUI
import UserNotifications

/// 把 Engine 发布的不可变快照转换为 SwiftUI 可观察状态（技术方案 14.1）。
///
/// 注意：`engine.snapshots` 是 AsyncStream，**非广播流**，多消费者会分流
/// （每个元素只送达一个迭代器）。因此 AppModel 是快照流的唯一消费者，
/// 其它 MainActor 消费者（如 OverlayPresenter）通过 `onSnapshotUpdate`
/// 转发，避免丢失或分流快照。
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: AppSnapshot?
    /// nil = 尚未确定；false = 通知权限未开启
    @Published private(set) var notificationAllowed: Bool?
    /// 具体授权状态描述，用于诊断
    @Published private(set) var notificationStatusDetail: String?
    /// 原始授权状态（设置页区分「未决定 / 已拒绝」的修复入口）。
    @Published private(set) var notificationAuthorizationStatus: UNAuthorizationStatus?
    /// 快照更新回调（AppEnvironment 注入，用于驱动 Overlay 等 MainActor 消费者）。
    var onSnapshotUpdate: (@MainActor (AppSnapshot?) -> Void)?
    private var task: Task<Void, Never>?

    init(engine: ReminderEngine) {
        task = Task { [weak self] in
            for await snapshot in engine.snapshots {
                self?.update(snapshot)
            }
        }
    }

    func set(_ snapshot: AppSnapshot) {
        update(snapshot)
    }

    private func update(_ snapshot: AppSnapshot?) {
        self.snapshot = snapshot
        onSnapshotUpdate?(snapshot)
    }

    func setNotificationAllowed(_ allowed: Bool?) {
        self.notificationAllowed = allowed
    }

    func setNotificationStatusDetail(_ detail: String?) {
        self.notificationStatusDetail = detail
    }

    func setNotificationAuthorizationStatus(_ status: UNAuthorizationStatus?) {
        self.notificationAuthorizationStatus = status
    }
}
