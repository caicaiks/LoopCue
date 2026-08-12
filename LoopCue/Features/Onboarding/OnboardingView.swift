import SwiftUI

/// 首次启动引导流（PRD 6.1 / 10.1 / 10.2）。
///
/// 说明 → 模板选择（自定义进入编辑器）→ 创建后申请通知权限
/// （技术方案 10.1：权限延后到创建首个提醒时）→ 可选登录时启动。
/// 引导窗口由 AppDelegate 以 AppKit 窗口承载，完成前应用不创建提醒、
/// 不申请权限。
struct OnboardingView: View {
    let appDelegate: AppDelegate

    @State private var step: Step = .intro
    @State private var showCustomEditor = false

    private enum Step {
        case intro
        case template
        case permission
        case login
    }

    var body: some View {
        Group {
            switch step {
            case .intro:
                introStep
            case .template:
                templateStep
            case .permission:
                permissionStep
            case .login:
                loginStep
            }
        }
        .frame(minWidth: 460, minHeight: 320)
        .sheet(isPresented: $showCustomEditor) {
            ReminderEditorView(
                draft: nil,
                defaults: EditorDefaults(
                    displayScope: appDelegate.settings.defaultDisplayScope,
                    awayPolicy: appDelegate.settings.defaultAwayPolicy
                )
            ) { config in
                appDelegate.send(.create(config))
                showCustomEditor = false
                step = .permission
            }
        }
    }

    // MARK: - 步骤

    private var introStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("让周期提醒真正有回应")
                .font(.title2)
                .bold()
            Text("叮刻会先轻轻提醒。如果你没有回应，它会按你的设置再次出现。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
            Button("创建第一个提醒") {
                step = .template
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private var templateStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择一个模板")
                .font(.title3)
                .bold()
            ForEach(ReminderTemplate.allCases) { template in
                Button {
                    choose(template)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .font(.headline)
                            Text(template.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Button("取消") {
                appDelegate.dismissOnboarding()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var permissionStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.badge")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("允许叮刻发送通知")
                .font(.title3)
                .bold()
            Text("弱提醒通过 macOS 通知发送。你可以直接在通知中完成或延后。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
            HStack(spacing: 12) {
                Button("稍后设置") {
                    step = .login
                }
                Button("继续") {
                    appDelegate.requestNotificationAuthorization()
                    step = .login
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private var loginStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "power")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("让叮刻常驻菜单栏")
                .font(.title3)
                .bold()
            Text("开启后登录时自动运行；关闭也不影响本次使用。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
            Toggle("登录时启动", isOn: Binding(
                get: { appDelegate.isLoginItemEnabled },
                set: { appDelegate.setLoginItemEnabled($0) }
            ))
            .toggleStyle(.switch)
            Button("完成") {
                appDelegate.settings.hasCompletedOnboarding = true
                appDelegate.dismissOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private func choose(_ template: ReminderTemplate) {
        if template == .custom {
            showCustomEditor = true
        } else {
            appDelegate.send(.create(template.makeConfig()))
            step = .permission
        }
    }
}
