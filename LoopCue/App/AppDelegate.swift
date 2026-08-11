import AppKit
import Foundation
import os

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var appModel: AppModel?
    @Published private(set) var launchError: String?
    private var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Self.ensureSingleInstance() else { return }
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
