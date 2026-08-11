import SwiftUI

@main
struct LoopCueApp: App {
    var body: some Scene {
        MenuBarExtra("叮刻 LoopCue", systemImage: "timer") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}

