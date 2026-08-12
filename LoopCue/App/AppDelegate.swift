import AppKit
import Foundation
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var appModel: AppModel?
    @Published private(set) var launchError: String?
    @Published private(set) var isLoginItemEnabled = false
    @Published private(set) var loginItemNeedsApproval = false
    private var environment: AppEnvironment?
    private let loginItem = LoginItemManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Self.ensureSingleInstance() else { return }
        refreshLoginItemStatus()
        do {
            let environment = try AppEnvironment()
            self.environment = environment
            self.appModel = environment.appModel
            environment.start()
        } catch {
            self.launchError = "\(error)"
            Logger(
                subsystem: "com.loopcue.LoopCue",
                category: "app"
            ).error("初始化失败: \(error, privacy: .public)")
        }
    }

    /// 菜单栏「清空数据并重新开始」入口。
    @MainActor
    func resetForTesting() {
        environment?.resetForTesting()
    }

    /// 刷新登录启动状态（启动与每次切换后调用）。
    @MainActor
    func refreshLoginItemStatus() {
        isLoginItemEnabled = loginItem.isEnabled
        loginItemNeedsApproval = loginItem.requiresApproval
    }

    /// 菜单栏「登录时启动」开关（PRD F-09）。
    @MainActor
    func setLoginItemEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try loginItem.enable()
            } else {
                try loginItem.disable()
            }
        } catch {
            Logger(
                subsystem: "com.loopcue.LoopCue",
                category: "app"
            ).error("登录启动切换失败: \(error, privacy: .public)")
        }
        refreshLoginItemStatus()
    }

    /// UI 层唯一写入口：把 Intent 交给 Engine（技术方案 4.1 / 15.1）。
    @MainActor
    func send(_ intent: ReminderIntent) {
        guard let engine = environment?.engine else { return }
        Task {
            try? await engine.handle(intent, now: Date())
        }
    }

    /// 菜单栏每次打开时刷新通知权限状态。
    @MainActor
    func refreshNotificationStatus() {
        environment?.checkNotificationPermission()
    }

    /// 只允许一个菜单栏实例：发现已有实例时激活旧实例并退出自身，
    /// 避免菜单栏出现两个相同的进程（重复 Run 或残留旧进程导致）。
    private static func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.loopcue.LoopCue"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return false
        }
        return true
    }
}
