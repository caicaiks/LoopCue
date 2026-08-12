import AppKit
import CoreGraphics
import Foundation

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
        isAwake = value
        lock.unlock()
        onContextChange?()
    }

    private func setSessionActive(_ value: Bool, refreshInput: Bool) {
        lock.lock()
        isSessionActive = value
        if refreshInput {
            lastInputAt = Date()
        }
        lock.unlock()
        onContextChange?()
    }

    private func clockChanged() {
        onContextChange?()
    }
}
