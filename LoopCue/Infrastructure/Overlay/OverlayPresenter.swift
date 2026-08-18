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
/// 展示内容由 Engine 发布的 AppSnapshot 驱动（单一数据源，经 AppModel
/// 转发；AsyncStream 非广播流，Overlay 不直接订阅 Engine）：
/// - 队列：同一时刻只展示 strongQueue 的第一项（主卡片），完成/跳过后
///   原地切换下一项；其余项显示「还有 N 项等待回应」。
/// - 多屏：displayScope == .all 时每个 NSScreen 建一个窗口；
///   == .current 时只覆盖鼠标所在屏（找不到回退主屏）。
/// - 热插拔：监听显示器变化通知，按需重建/校正窗口，不写业务状态。
/// - 抑制：Escape / 暂时关闭后轮次仍为 strongPending 但带
///   overlaySuppressionRemaining；AppSnapshot 已将其排除出队列，
///   5 分钟有效时长后再现。
/// 事件回调只发 Intent（complete / skip / snooze / dismissOverlay），
/// 不直接写状态（技术方案 4.1）。
@MainActor
final class OverlayPresenter: OverlayPresenting {
    private var panels: [NSPanel] = []
    /// 当前已渲染的主卡片签名（cycleID、队列数、屏数），避免每秒快照重复重建。
    private var rendered: (cycleID: UUID, queueCount: Int, screenCount: Int)?
    private var currentSnapshot: AppSnapshot?
    private var screenObserver: NSObjectProtocol?

    private let onComplete: (UUID, UUID) -> Void
    private let onSkip: (UUID, UUID) -> Void
    private let onSnooze: (UUID, UUID) -> Void
    private let onDismiss: (UUID, UUID) -> Void

    init(
        onComplete: @escaping (UUID, UUID) -> Void,
        onSkip: @escaping (UUID, UUID) -> Void,
        onSnooze: @escaping (UUID, UUID) -> Void,
        onDismiss: @escaping (UUID, UUID) -> Void
    ) {
        self.onComplete = onComplete
        self.onSkip = onSkip
        self.onSnooze = onSnooze
        self.onDismiss = onDismiss
        // 显示器热插拔 / 分辨率变化：重建或校正窗口，不触发任何业务状态变化。
        // 观察者按 queue: .main 派发，因此 assumeIsolated 是安全的。
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.render()
            }
        }
    }

    /// AppEnvironment 注入：AppModel 每次发布快照时调用（唯一数据源）。
    func update(snapshot: AppSnapshot?) {
        currentSnapshot = snapshot
        render()
    }

    // MARK: - OverlayPresenting

    /// Outbox 信号：展示由快照驱动，这里只需触发一次重渲染，
    /// 保证效应消费顺序与快照发布顺序不一致时也能收敛。
    func present(reminderID: UUID, cycleID: UUID) async {
        render()
    }

    func dismiss(reminderID: UUID, cycleID: UUID) async {
        render()
    }

    // MARK: - 渲染

    private func render() {
        guard let snapshot = currentSnapshot else { return }
        guard let primary = snapshot.strongQueue.first else {
            teardownPanels()
            rendered = nil
            return
        }
        let targetScreens = screens(for: primary.displayScope)
        let signature = (primary.cycleID, snapshot.strongQueue.count, targetScreens.count)

        // 主卡片、队列数、屏数都没变 → 只校正 frame（分辨率/排列变化）。
        if let rendered, rendered == signature {
            applyFrames()
            return
        }

        teardownPanels()
        rendered = signature
        buildPanels(for: primary, queueCount: snapshot.strongQueue.count, screens: targetScreens)
    }

    /// 目标屏幕集合：all 覆盖所有显示器；current 覆盖鼠标所在屏（回退主屏）。
    private func screens(for scope: DisplayScope) -> [NSScreen] {
        switch scope {
        case .all:
            return NSScreen.screens
        case .current:
            let mouse = NSEvent.mouseLocation
            let target = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            return [target ?? NSScreen.screens.first].compactMap { $0 }
        }
    }

    private func buildPanels(
        for item: StrongReminderSnapshot,
        queueCount: Int,
        screens: [NSScreen]
    ) {
        guard !screens.isEmpty else { return }
        // 菜单栏（accessory）应用需要先激活自身，覆盖窗口才能带到最前。
        NSApp.activate(ignoringOtherApps: true)
        var built: [NSPanel] = []
        for screen in screens {
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
            panel.backgroundColor = .clear
            panel.contentView = NSHostingView(
                rootView: StrongReminderView(
                    item: item,
                    queueCount: queueCount,
                    onComplete: onComplete,
                    onSkip: onSkip,
                    onSnooze: onSnooze,
                    onDismiss: onDismiss
                )
            )
            panel.makeKeyAndOrderFront(nil)
            built.append(panel)
        }
        // 主卡片窗口设为 key window，让键盘焦点落在完成按钮。
        built.first?.makeKeyAndOrderFront(nil)
        panels = built
    }

    /// 显示器数量不变时的帧校正（分辨率 / 排列变化）。
    private func applyFrames() {
        for (index, screen) in NSScreen.screens.enumerated()
        where panels.indices.contains(index) {
            panels[index].setFrame(screen.frame, display: true)
        }
    }

    private func teardownPanels() {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }
}
