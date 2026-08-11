import AppKit
import Foundation
import SwiftUI

/// borderless 样式的 NSPanel 默认不能成为 key window，
/// 会导致按钮点击/键盘事件不可达。覆写后让覆盖窗口可交互。
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

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
    private let onDismiss: (UUID, UUID) -> Void

    init(
        onComplete: @escaping (UUID, UUID) -> Void,
        onDismiss: @escaping (UUID, UUID) -> Void
    ) {
        self.onComplete = onComplete
        self.onDismiss = onDismiss
    }

    func present(reminderID: UUID, cycleID: UUID) async {
        guard panelsByCycle[cycleID] == nil else { return } // 幂等
        // 菜单栏（accessory）应用需要先激活自身，覆盖窗口才能带到最前。
        NSApp.activate(ignoringOtherApps: true)
        var panels: [NSPanel] = []
        for screen in NSScreen.screens {
            let panel = OverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .black.withAlphaComponent(0.88)
            panel.contentView = NSHostingView(
                rootView: StrongReminderView(
                    reminderID: reminderID,
                    cycleID: cycleID,
                    onComplete: onComplete,
                    onDismiss: onDismiss
                )
            )
            panel.makeKeyAndOrderFront(nil)
            panels.append(panel)
        }
        // 窗口已在最前，设置 key window 让键盘焦点落在完成按钮。
        panels.first?.makeKeyAndOrderFront(nil)
        panelsByCycle[cycleID] = panels
    }

    func dismiss(reminderID: UUID, cycleID: UUID) async {
        guard let panels = panelsByCycle.removeValue(forKey: cycleID) else { return }
        for panel in panels {
            panel.orderOut(nil)
        }
    }
}
