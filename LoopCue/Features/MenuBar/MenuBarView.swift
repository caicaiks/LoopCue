import SwiftUI

/// 菜单栏主界面：展示 Engine 快照中的提醒与阶段（技术方案 14.2）。
struct MenuBarView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("叮刻 LoopCue")
                .font(.headline)

            if let snapshot = appModel.snapshot {
                if snapshot.reminders.isEmpty {
                    Text("暂无提醒")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.reminders) { reminder in
                        HStack {
                            Image(systemName: reminder.config.icon.rawValue)
                            Text(reminder.config.name)
                            Spacer()
                            Text(phaseLabel(reminder.phase))
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            } else {
                Text("加载中…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 260)
    }

    private func phaseLabel(_ phase: CyclePhase?) -> String {
        switch phase {
        case .counting: return "计时中"
        case .weakPending: return "等待回应"
        case .snoozed: return "已延后"
        case .strongPending: return "等待升级"
        case nil: return "—"
        }
    }
}

