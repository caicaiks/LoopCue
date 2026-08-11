import Foundation
import SwiftUI

/// 把 Engine 发布的不可变快照转换为 SwiftUI 可观察状态（技术方案 14.1）。
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: AppSnapshot?
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
}

