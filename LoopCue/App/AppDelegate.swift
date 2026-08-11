import AppKit
import Foundation
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private(set) var appModel: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let environment = try AppEnvironment()
            self.environment = environment
            self.appModel = environment.appModel
            environment.start()
        } catch {
            Logger(
                subsystem: "com.loopcue.LoopCue",
                category: "app"
            ).error("初始化失败: \(error, privacy: .public)")
        }
    }
}

