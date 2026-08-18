import AppKit
import Combine
import Foundation
import os
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var appModel: AppModel?
    @Published private(set) var launchError: String?
    @Published private(set) var isLoginItemEnabled = false
    @Published private(set) var loginItemNeedsApproval = false
    /// 需要展示首次启动引导（提醒为空且未完成过引导）。
    @Published private(set) var needsOnboarding = false
    let settings = AppSettingsStore()
    private var environment: AppEnvironment?
    private let loginItem = LoginItemManager()
    private var cancellables: Set<AnyCancellable> = []
    private var onboardingWindow: NSWindow?
    /// 引导会话进行中：创建首个提醒后快照不再为空，但流程尚未结束，
    /// 不能据此关闭引导窗口。
    private var onboardingSessionActive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单元测试宿主进程也会走到这里；跳过启动逻辑，避免
        // 单实例保护终止测试宿主，也避免测试运行触碰真实数据存储。
        if NSClassFromString("XCTestCase") != nil {
            return
        }
        guard Self.ensureSingleInstance() else { return }
        refreshLoginItemStatus()
        do {
            let environment = try AppEnvironment()
            self.environment = environment
            self.appModel = environment.appModel
            observeOnboardingState()
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

    /// 删除所有本地数据（设置页，二次确认后调用）。
    /// 清空业务数据后移除全部通知，回到全新状态（onboarding 待 Step 3）。
    @MainActor
    func deleteAllLocalData() {
        Task {
            try? await environment?.engine.clearAll(now: Date())
            NotificationCleanup.removeAll()
            // 删除全部数据后重新进入 onboarding（PRD 16.2）。
            settings.hasCompletedOnboarding = false
        }
    }

    /// Onboarding 完成时调用：关闭引导窗口。
    @MainActor
    func dismissOnboarding() {
        onboardingWindow?.orderOut(nil)
        onboardingWindow = nil
        refreshOnboarding()
    }

    /// 按需申请通知权限（Onboarding 权限步骤，PRD 10.2）。
    @MainActor
    func requestNotificationAuthorization() {
        Task {
            await environment?.requestNotificationAuthorization()
            refreshNotificationStatus()
        }
    }

    /// 通知权限状态变化后由 AppModel 快照驱动：提醒为空且未完成引导时展示。
    private func observeOnboardingState() {
        guard let appModel else { return }
        appModel.$snapshot
            .sink { [weak self] snapshot in
                guard let snapshot else { return } // 初始 nil 不发窗口
                guard !(self?.onboardingSessionActive ?? false) else { return }
                self?.refreshOnboarding(remindersEmpty: snapshot.reminders.isEmpty)
            }
            .store(in: &cancellables)
    }

    private func refreshOnboarding(remindersEmpty: Bool? = nil) {
        let empty = remindersEmpty ?? (appModel?.snapshot?.reminders.isEmpty ?? true)
        needsOnboarding = empty && !settings.hasCompletedOnboarding
        if needsOnboarding {
            presentOnboarding()
        } else {
            onboardingWindow?.orderOut(nil)
            onboardingWindow = nil
            onboardingSessionActive = false
        }
    }

    /// 以 AppKit 窗口承载 SwiftUI OnboardingView（菜单栏应用无常驻 Scene，
    /// 直接管理窗口最可靠，与 OverlayPresenter 的 NSPanel 思路一致）。
    private func presentOnboarding() {
        guard onboardingWindow == nil else {
            onboardingWindow?.makeKeyAndOrderFront(nil)
            return
        }
        onboardingSessionActive = true
        let hosting = NSHostingController(
            rootView: OnboardingView(appDelegate: self)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "欢迎使用叮刻"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
