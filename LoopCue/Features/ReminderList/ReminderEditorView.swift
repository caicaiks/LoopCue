import SwiftUI

/// 新建 / 编辑提醒的表单（PRD F-01 / 技术方案 5 Features/ReminderEditor）。
///
/// 保存时在 Domain 层统一校验，失败给出就地错误提示；
/// 生效方式（下一轮 / 立即）由外层在编辑运行中提醒时确认。
struct ReminderEditorView: View {
    let draft: ReminderConfig?
    let onSave: (ReminderConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var icon: ReminderIcon
    @State private var message: String
    @State private var completionLabel: String
    @State private var intervalMinutes: Int
    @State private var escalationEnabled: Bool
    @State private var escalationMinutes: Int
    @State private var snoozeMinutes: Int
    @State private var maxSnoozeCount: Int
    @State private var awayKind: AwayKind
    @State private var awayMinutes: Int
    @State private var isEnabled: Bool
    @State private var validationError: String?

    init(draft: ReminderConfig?, onSave: @escaping (ReminderConfig) -> Void) {
        self.draft = draft
        self.onSave = onSave

        _name = State(initialValue: draft?.name ?? "自定义提醒")
        _icon = State(initialValue: draft?.icon ?? .custom)
        _message = State(initialValue: draft?.message ?? "")
        _completionLabel = State(initialValue: draft?.completionLabel ?? "已完成")
        _intervalMinutes = State(initialValue: Self.minutes(of: draft?.interval) ?? 60)
        _escalationEnabled = State(initialValue: draft?.escalationDelay != nil)
        _escalationMinutes = State(initialValue: Self.minutes(of: draft?.escalationDelay) ?? 15)
        _snoozeMinutes = State(initialValue: Self.minutes(of: draft?.snoozeDuration) ?? 10)
        _maxSnoozeCount = State(initialValue: draft?.maxSnoozeCount ?? 2)
        let policy = draft?.awayPolicy ?? .pause(threshold: .minutes(5))
        _awayKind = State(initialValue: Self.kind(of: policy))
        _awayMinutes = State(initialValue: Self.thresholdMinutes(of: policy))
        _isEnabled = State(initialValue: draft?.isEnabled ?? true)
    }

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("名称", text: $name)
                Picker("图标", selection: $icon) {
                    ForEach(ReminderIcon.allCases, id: \.self) { item in
                        Label(item.rawValue, systemImage: item.rawValue).tag(item)
                    }
                }
                TextField("弱提醒文案", text: $message)
                TextField("完成按钮文案", text: $completionLabel)
            }

            Section("计时") {
                Stepper("周期：\(intervalMinutes) 分钟", value: $intervalMinutes, in: 5...1440)
                Toggle("未回应升级为全屏提醒", isOn: $escalationEnabled)
                if escalationEnabled {
                    Stepper("等待 \(escalationMinutes) 分钟", value: $escalationMinutes, in: 1...1440)
                }
            }

            Section("延后") {
                Stepper("延后时长：\(snoozeMinutes) 分钟", value: $snoozeMinutes, in: 1...1440)
                Stepper("每轮最多 \(maxSnoozeCount) 次", value: $maxSnoozeCount, in: 0...10)
            }

            Section("离开电脑") {
                Picker("策略", selection: $awayKind) {
                    Text("暂停计时").tag(AwayKind.pause)
                    Text("视为完成").tag(AwayKind.complete)
                }
                Stepper("阈值：\(awayMinutes) 分钟", value: $awayMinutes, in: 1...120)
            }

            Section {
                Toggle("启用", isOn: $isEnabled)
            }

            if let validationError {
                Section {
                    Text(validationError)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(draft == nil ? "新建提醒" : "编辑提醒")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(minWidth: 440, minHeight: 460)
    }

    private func save() {
        let config = buildConfig()
        switch ReminderValidation.validate(config) {
        case .success:
            onSave(config)
        case .failure(let error):
            validationError = Self.message(for: error)
        }
    }

    private func buildConfig() -> ReminderConfig {
        let base = draft ?? ReminderTemplate.custom.makeConfig()
        var config = base
        config.name = name
        config.icon = icon
        config.message = message
        config.completionLabel = completionLabel
        config.interval = UIFormatters.duration(minutes: intervalMinutes)
        config.escalationDelay = escalationEnabled
            ? UIFormatters.duration(minutes: escalationMinutes)
            : nil
        config.snoozeDuration = UIFormatters.duration(minutes: snoozeMinutes)
        config.maxSnoozeCount = maxSnoozeCount
        config.awayPolicy = awayKind == .pause
            ? .pause(threshold: UIFormatters.duration(minutes: awayMinutes))
            : .complete(threshold: UIFormatters.duration(minutes: awayMinutes))
        config.isEnabled = isEnabled
        return config
    }

    private static func minutes(of duration: Duration?) -> Int? {
        guard let duration else { return nil }
        return Int(duration.components.seconds) / 60
    }

    private static func kind(of policy: AwayPolicy) -> AwayKind {
        switch policy {
        case .pause: return .pause
        case .complete: return .complete
        }
    }

    private static func thresholdMinutes(of policy: AwayPolicy) -> Int {
        switch policy {
        case .pause(let threshold): return Int(threshold.components.seconds) / 60
        case .complete(let threshold): return Int(threshold.components.seconds) / 60
        }
    }

    private static func message(for error: ReminderValidationError) -> String {
        switch error {
        case .nameTooShort: return "名称至少 1 个字符"
        case .nameTooLong: return "名称最多 20 个字符"
        case .messageTooLong: return "弱提醒文案最多 80 个字符"
        case .completionLabelTooShort: return "完成按钮文案至少 1 个字符"
        case .completionLabelTooLong: return "完成按钮文案最多 8 个字符"
        case .intervalOutOfRange: return "周期需在 5 分钟～24 小时之间"
        case .escalationDelayOutOfRange: return "升级等待需在 1 分钟～24 小时之间"
        case .snoozeDurationOutOfRange: return "延后时长需在 1 分钟～24 小时之间"
        case .snoozeCountOutOfRange: return "延后次数需在 0～10 之间"
        }
    }
}

/// 离开电脑策略的编辑形态（AwayPolicy 带关联值，Picker 无法直接 tag）。
private enum AwayKind: Hashable {
    case pause
    case complete
}
