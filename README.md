# 叮刻 LoopCue

> 不只提醒时间，也等待你的回应。

LoopCue（叮刻）是一款 macOS 菜单栏常驻的渐进式周期提醒器：先以系统通知轻提醒，未收到回执时按配置升级为全屏强提醒，直到用户完成或跳过。本地优先，无账号、无网络依赖。

## 当前状态

- 文档阶段已完成：PRD、技术方案、规范速览、AGENTS.md。
- M0 进行中：Xcode 工程骨架已就绪，领域内核（ReminderReducer / Scheduler / Core Data）待实现。

## 目录结构

```text
LoopCue/
├── LoopCue.xcodeproj          # xcodegen 生成，提交进仓库可直接打开
├── project.yml                # 工程描述，改动结构后运行 xcodegen generate 重新生成
├── LoopCue/
│   ├── App/                   # @main 入口、AppDelegate、环境
│   ├── Domain/                # 纯领域层：模型、Intent、Reducer、Effect
│   ├── Application/           # Engine、Scheduler、EffectDispatcher、系统上下文
│   ├── Infrastructure/        # Core Data、通知、全屏窗口、空闲检测、登录启动
│   ├── Features/              # 菜单栏、列表、编辑、Onboarding、设置、强提醒
│   └── Resources/             # Info.plist、Assets、本地化
├── LoopCueTests/              # 单元测试（Domain / Scheduler / Persistence）
└── docs/                      # PRD、技术方案、规范速览
```

## 快速开始

```bash
# 1. 生成并打开工程（结构变更后需重新生成）
xcodegen generate
open LoopCue.xcodeproj

# 2. 命令行构建与测试
xcodebuild -project LoopCue.xcodeproj -scheme LoopCue -destination 'platform=macOS' build
xcodebuild -project LoopCue.xcodeproj -scheme LoopCue -destination 'platform=macOS' test
```

## 文档

| 文档 | 说明 |
| --- | --- |
| `docs/LoopCue-PRD-v0.1.md` | 产品需求文档 |
| `docs/LoopCue-Technical-Design-v0.1.md` | 技术方案 |
| `docs/macOS-Dev-Specs-Reference-v0.1.md` | 外部规范速览 |
| `AGENTS.md` | 面向 AI 编码 agent 的项目指引 |

## License

暂未选择开源协议，保留所有权利。

