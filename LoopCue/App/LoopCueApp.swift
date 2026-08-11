import SwiftUI

@main
struct LoopCueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("叮刻 LoopCue", systemImage: "timer") {
            if let appModel = appDelegate.appModel {
                MenuBarView(appModel: appModel)
            } else {
                Text("初始化中…")
                    .padding()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
