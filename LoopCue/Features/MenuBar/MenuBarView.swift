import SwiftUI

/// 菜单栏主界面占位（M0 骨架）。
///
/// 后续替换为 ReminderEngine 发布的 AppSnapshot 驱动的内容。
struct MenuBarView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("叮刻 LoopCue")
                .font(.headline)
            Text("提醒引擎尚未接入，当前为 M0 工程骨架。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 240)
    }
}

