import AppKit
import Foundation
import SwiftUI

/// 全屏强提醒展示抽象（供 EffectExecutor 调用）。
protocol OverlayPresenting: Sendable {
    func present(reminderID: UUID, cycleID: UUID) async
    func dismiss(reminderID: UUID, cycleID: UUID) async
}

/// 基于 NSPanel 的多显示器全屏覆盖窗口（技术方案 11）。
///
/// 每个 NSScreen 创建一个无边框 panel，加入所有 Space 并可覆盖原生全屏
/// 应用；不承诺阻止 Cmd+Tab 等系统逃生方式。窗口层级、Space、热插拔
/// 行为属于 M0-A 真机验证项，此处先接入可运行的最小实现。
@MainActor
final class OverlayPresenter: OverlayPresenting {
    private var panelsByCycle: [UUID: [NSPanel]] = [:]
    private let onComplete: (UUID, UUID) -> Void

    init(onComplete: @escaping (UUID, UUID) -> Void) {
        self.onComplete = onComplete
    }

    func present(reminderID: UUID, cycleID: UUID) async {
        guard panelsByCycle[cycleID] == nil else { return } // 幂等
        var panels: [NSPanel] = []
        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .modalPanel
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .black.withAlphaComponent(0.88)
            panel.contentView = NSHostingView(
                rootView: StrongReminderView(
                    reminderID: reminderID,
                    cycleID: cycleID,
                    onComplete: onComplete
                )
            )
            panel.makeKeyAndOrderFront(nil)
            panels.append(panel)
        }
        panelsByCycle[cycleID] = panels
    }

    func dismiss(reminderID: UUID, cycleID: UUID) async {
        guard let panels = panelsByCycle.removeValue(forKey: cycleID) else { return }
        for panel in panels {
            panel.orderOut(nil)
        }
    }
}
