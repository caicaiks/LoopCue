import SwiftUI

/// 提醒列表主窗口（PRD F-09 / 技术方案 5 Features/ReminderList）。
///
/// 支持新建、编辑、启停与删除（删除等待回应中的提醒需二次确认），
/// 编辑运行中的提醒时确认生效方式（下一轮 / 立即）。
struct ReminderListView: View {
    @ObservedObject var appDelegate: AppDelegate

    @State private var editor: EditorTarget?
    @State private var pendingDelete: ReminderSnapshot?
    @State private var pendingApplyEdit: (config: ReminderConfig, original: ReminderSnapshot)?

    private var snapshot: AppSnapshot? { appDelegate.appModel?.snapshot }

    private enum EditorTarget: Identifiable {
        case create
        case edit(ReminderSnapshot)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let reminder): return reminder.id.uuidString
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot {
                if snapshot.reminders.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("暂无提醒")
                            .font(.headline)
                        Text("点击右上角「新建提醒」，或从模板开始。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(snapshot.reminders) { reminder in
                            row(reminder, snapshotNow: snapshot.now)
                        }
                    }
                    .listStyle(.inset)
                }
            } else {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("提醒列表")
        .frame(minWidth: 560, minHeight: 420)
        .toolbar {
            ToolbarItem {
                Button {
                    editor = .create
                } label: {
                    Label("新建提醒", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editor) { target in
            switch target {
            case .create:
                ReminderEditorView(
                    draft: nil,
                    defaults: EditorDefaults(
                        displayScope: appDelegate.settings.defaultDisplayScope,
                        awayPolicy: appDelegate.settings.defaultAwayPolicy
                    )
                ) { config in
                    appDelegate.send(.create(config))
                    editor = nil
                }
            case .edit(let reminder):
                ReminderEditorView(draft: reminder.config) { config in
                    editor = nil
                    if reminder.phase != nil {
                        pendingApplyEdit = (config: config, original: reminder)
                    } else {
                        appDelegate.send(.update(reminder.id, config, .nextCycle))
                    }
                }
            }
        }
        .confirmationDialog(
            "新设置如何生效？",
            isPresented: Binding(
                get: { pendingApplyEdit != nil },
                set: { if !$0 { pendingApplyEdit = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("从下一轮生效（推荐）") { applyEdit(.nextCycle) }
            Button("立即应用（可能马上提醒）") { applyEdit(.immediate) }
            Button("取消", role: .cancel) { pendingApplyEdit = nil }
        } message: {
            Text("编辑当前正在进行的一轮时，新设置默认从下一轮生效。立即应用会按新阈值重新计算，可能立刻触发提醒。")
        }
        .confirmationDialog(
            "删除提醒？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let reminder = pendingDelete {
                    appDelegate.send(.delete(reminder.id))
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("将删除「\(pendingDelete?.config.name ?? "")」及其相关记录，并取消未送达的通知。")
        }
    }

    private func row(_ reminder: ReminderSnapshot, snapshotNow: Date) -> some View {
        HStack(spacing: 10) {
            Image(systemName: reminder.config.icon.rawValue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.config.name)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(statusText(reminder, since: snapshotNow, now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { reminder.config.isEnabled },
                set: { appDelegate.send(.setEnabled(reminder.id, $0)) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            if reminder.isPaused {
                Button("恢复") {
                    appDelegate.send(.resumeReminder(reminder.id))
                }
            } else {
                Menu {
                    Button("暂停 30 分钟") {
                        appDelegate.send(.pauseReminder(reminder.id, .timed(.minutes(30))))
                    }
                    Button("暂停 1 小时") {
                        appDelegate.send(.pauseReminder(reminder.id, .timed(.hours(1))))
                    }
                    Button("暂停到明天") {
                        appDelegate.send(.pauseReminder(reminder.id, .untilMidnight))
                    }
                    Button("一直暂停") {
                        appDelegate.send(.pauseReminder(reminder.id, .indefinite))
                    }
                } label: {
                    Image(systemName: "pause.fill")
                }
            }
            Button("编辑") {
                editor = .edit(reminder)
            }
            Button(role: .destructive) {
                pendingDelete = reminder
            } label: {
                Image(systemName: "trash")
            }
        }
        .padding(.vertical, 2)
    }

    private func statusText(
        _ reminder: ReminderSnapshot,
        since snapshotNow: Date,
        now: Date
    ) -> String {
        switch reminder.phase {
        case .counting:
            if let remaining = reminder.remainingToWeak {
                return "计时中 · \(UIFormatters.countdown(remaining, since: snapshotNow, now: now)) 后弱提醒"
            }
            return "计时中"
        case .weakPending:
            if let remaining = escalationRemaining(of: reminder) {
                return "等待回应 · \(UIFormatters.countdown(remaining, since: snapshotNow, now: now)) 后升级"
            }
            return "等待回应"
        case .snoozed:
            return "已延后"
        case .strongPending:
            return "等待升级（全屏提醒中）"
        case nil:
            return "—"
        }
    }

    private func escalationRemaining(of reminder: ReminderSnapshot) -> Duration? {
        guard let delay = reminder.escalationDelay else { return nil }
        return max(.zero, delay - reminder.escalationElapsed)
    }

    private func applyEdit(_ mode: ApplyMode) {
        guard let pending = pendingApplyEdit else { return }
        appDelegate.send(.update(pending.original.id, pending.config, mode))
        pendingApplyEdit = nil
    }
}
