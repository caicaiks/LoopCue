import AppKit
import CoreGraphics
import Foundation
import os

/// 只读取「距离上次键鼠输入的时长」的空闲检测（技术方案 8.6）。
protocol IdleTimeProviding: Sendable {
    func idleDuration() -> Duration?
}

struct CoreGraphicsIdleTimeProvider: IdleTimeProviding {
    func idleDuration() -> Duration? {
        guard let anyInput = CGEventType(rawValue: UInt32.max) else { return nil }
        let seconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInput
        )
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return .seconds(Int64(seconds))
    }
}

/// 系统上下文监控（技术方案 12.1 / 8.6）。
///
/// 监听睡眠/唤醒、锁屏/解锁、系统改时；`currentContext` 每次读取系统
/// 聚合空闲时长并反推最近输入时间。事件变化通过 `onContextChange` 触发
/// Engine reconcile。不读取按键内容、鼠标位置或应用内容。
final class SystemContextMonitor: SystemContextProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let idleProvider: any IdleTimeProviding
    private var isAwake = true
    private var isSessionActive = true
    private var lastInputAt: Date?
    private var observers: [NSObjectProtocol] = []
    private var onContextChange: (() -> Void)?
    /// 子系统日志（技术方案 17）：只记录 active/idle 与睡眠/锁屏状态变化，
    /// 不记录具体输入内容、提醒正文或用户输入。
    private static let logger = Logger(
        subsystem: "com.loopcue.LoopCue",
        category: "activity"
    )

    init(idleProvider: any IdleTimeProviding = CoreGraphicsIdleTimeProvider()) {
        self.idleProvider = idleProvider
    }

    func start(onContextChange: @escaping () -> Void) {
        self.onContextChange = onContextChange
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let defaultCenter = NotificationCenter.default

        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setAwake(false)
        })
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setAwake(true)
        })
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setSessionActive(false, refreshInput: false)
        })
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setSessionActive(true, refreshInput: true)
        })
        observers.append(defaultCenter.addObserver(
            forName: .NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clockChanged()
        })
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    func currentContext(now: Date) -> SystemContext {
        lock.lock()
        defer { lock.unlock() }
        if let idle = idleProvider.idleDuration() {
            lastInputAt = now.addingTimeInterval(-TimeInterval(idle.components.seconds))
        }
        return SystemContext(
            now: now,
            isAwake: isAwake,
            isSessionActive: isSessionActive,
            idleDuration: idleProvider.idleDuration() ?? .zero,
            lastInputAt: lastInputAt,
            calendar: .autoupdatingCurrent
        )
    }

    private func setAwake(_ value: Bool) {
        lock.lock()
        let changed = isAwake != value
        isAwake = value
        lock.unlock()
        if changed {
            Self.logger.info("睡眠状态变化: awake=\(value, privacy: .public)")
        }
        onContextChange?()
    }

    private func setSessionActive(_ value: Bool, refreshInput: Bool) {
        lock.lock()
        let changed = isSessionActive != value
        isSessionActive = value
        if refreshInput {
            lastInputAt = Date()
        }
        lock.unlock()
        if changed {
            Self.logger.info("会话状态变化: active=\(value, privacy: .public)")
        }
        onContextChange?()
    }

    private func clockChanged() {
        Self.logger.notice("系统时间变化，触发重算")
        onContextChange?()
    }
}
