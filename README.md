# 叮刻 LoopCue

> 不只提醒时间，也等待你的回应。

LoopCue（叮刻）是一款 macOS 菜单栏常驻的渐进式周期提醒器：先以系统通知轻提醒，未收到回执时按配置升级为全屏强提醒，直到用户完成或跳过。本地优先，无账号、无网络依赖。

## 当前状态

- 文档阶段已完成：PRD、技术方案、规范速览、AGENTS.md。
- M0 已完成：工程骨架、领域内核、纵向闭环核心（Engine / Core Data 持久化 / Outbox / EffectDispatcher）、通知回执与全屏 Overlay。
- M1-A 进行中：四模板（起身/喝水/远眺/自定义）、提醒列表与新建/编辑/启停/删除、编辑「下一轮/立即」生效、菜单栏下一项与等待回应快捷操作已完成，51 个单元测试通过。
- 待办：强提醒多卡队列、睡眠/锁屏/闲置门控（M1-B）、生效时段、多屏热插拔与设置页（M1-C）。

## 目录结构

```text
LoopCue/
├── LoopCue.xcodeproj          # xcodegen 生成，仅本地保留（已 gitignore）
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
# 1. 查看全部命令
make help

# 2. 生成工程并打开（结构变更后自动重新生成）
xcodegen generate
open LoopCue.xcodeproj

# 3. 常用命令（等价于 scripts/ 下的脚本）
make generate   # 重新生成 .xcodeproj
make build      # Debug 构建
make release    # Release 构建
make test       # 运行全部单元测试
make clean      # 清理本地构建产物
make open       # 生成并打开 Xcode
```

说明：`make test` 的单元测试运行器需要连接系统 `testmanagerd` 服务，必须在沙盒外（例如你的终端）执行；`make build` / `make generate` 可在受限环境运行。构建产物统一输出到 `.build/DerivedData`（已被 gitignore 排除）。

### 测试提示

- **Debug 时间倍率**：Debug 构建下时间推进为 10 倍速，「起身活动」默认 30 分钟提醒实际约 3 分钟触发，方便真机验证闭环。Release 恒为真实时间，该倍率不会进入 Release 构建。
- **每次启动重新计时**：当前版本每次启动都会把提醒重置为全新一轮（保留配置，清空事件与待处理效果），不会恢复上一轮的计时状态。
- **单实例保护**：应用只允许一个菜单栏实例。若仍看到两个图标，说明存在修复前的残留进程，先退出旧实例再启动。

## 文档

| 文档 | 说明 |
| --- | --- |
| `docs/LoopCue-PRD-v0.1.md` | 产品需求文档 |
| `docs/LoopCue-Technical-Design-v0.1.md` | 技术方案 |
| `docs/macOS-Dev-Specs-Reference-v0.1.md` | 外部规范速览 |
| `AGENTS.md` | 面向 AI 编码 agent 的项目指引 |

## License

暂未选择开源协议，保留所有权利。
