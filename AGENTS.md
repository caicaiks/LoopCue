# AGENTS.md

本文件为在 LoopCue 仓库中工作的 AI 编码 agent 提供项目级指引。开始任何实现工作前，先通读《LoopCue PRD v0.1》与《LoopCue 技术方案 v0.1》。

## 项目概览

LoopCue（叮刻）是一个 macOS 菜单栏常驻应用：渐进式周期提醒器。核心闭环是「弱提醒 → 等待回执 → 未回应 → 升级为全屏强提醒 → 完成/跳过重置新一轮」。产品形态为单进程菜单栏 Agent（LSUIElement），本地优先、无账号、无网络依赖。

## 文档导航

| 文档 | 作用 |
| --- | --- |
| `docs/LoopCue-PRD-v0.1.md` | 产品需求：P0 功能、状态机语义、验收测试清单、非目标 |
| `docs/LoopCue-Technical-Design-v0.1.md` | 架构落地方案：模块划分、时间模型、并发、里程碑拆分 |
| `docs/LoopCue-Development-Progress-v0.1.md` | 开发进展与待办（持续更新）：已完成项、最近改动、已知问题、真机验证清单 |
| `docs/macOS-Dev-Specs-Reference-v0.1.md` | 外部规范速览：HIG、App Review、Sandbox、风格指南 |

仓库已完成 M0 与 M1（A/B/C）全部代码，117 个单元测试全部通过，当前处于「M1-C 真机验证 + M2 加固」阶段。工程由 XcodeGen 生成（`project.yml` 是唯一事实来源，`.xcodeproj` 仅本地保留）；动工前先读《开发进展记录》中的待办与真机清单，结构变更后运行 `make generate` 重新生成工程。

## 技术栈与约束

- 最低系统：macOS 13 Ventura。
- 语言与 UI：Swift、SwiftUI 为主，AppKit 负责状态栏与多显示器全屏覆盖窗口。
- 持久化：Core Data（SQLite Store）；设置项可用 `UserDefaults`。
- 通知：`UNUserNotificationCenter`，带操作按钮的动态 Category。
- 登录启动：`SMAppService`。
- MVP 不引入第三方依赖。
- 应用形态：单进程，`Info.plist` 设置 `LSUIElement = YES`。
- 沙盒：开启 App Sandbox，entitlements 最小化；不申请网络、输入监听、辅助功能、摄像头/麦克风。

## 架构红线（技术方案 4、7、8）

- `ReminderEngine`（actor）是唯一业务写入口；通知、菜单栏、全屏界面只发 Intent，不直接写状态。
- `Timer` 只用于唤醒和 UI 刷新，不是时间事实来源；业务状态由持久化的累计有效时长推导。
- 时间模型：运行期间用单调时钟，落盘保存累计秒数；墙上时间只用于工作日、生效时段、事件时间和界面显示。
- 状态转换与系统副作用（Outbox Effect）在同一事务内落盘；重启后通过 Outbox 补发。
- 所有回执 Intent 携带 `cycleID`；过期 cycleID 必须忽略，保证幂等。
- Domain 层为纯函数（Reducer），不依赖 SwiftUI / AppKit / Core Data；时间与日历通过注入（FakeClock）测试。
- 睡眠、锁屏、闲置、非生效时段、暂停期间一律不累计有效时长。
- 强提醒（全屏覆盖）必须始终提供 Escape 等安全退出方式，不承诺不可绕过的锁定。

## 代码约定

- 遵循 Swift API Design Guidelines；从技术方案 5 中选定一套社区风格指南（参考 `macOS-Dev-Specs-Reference` 3.1～3.3）作为评审基线。
- 跨层只传 Sendable 值类型，`NSManagedObject` 与 AppKit 对象不跨 actor。
- UI 只展示 Engine 发布的不可变 Snapshot，禁止各页面自行推导业务状态。
- 日志用 `os.Logger`，按子系统拆分；不得记录提醒正文、完成文案或用户输入。
- Debug 才可启用时间倍率/上下文注入的测试开关，Release 必须排除，禁止隐藏开关修改生产数据。

## 测试要求（技术方案 19）

- Domain：`ReminderReducer` 核心状态机单元测试（TestClock、FakeIdleProvider）。
- Scheduler：睡眠/锁屏不累计、闲置边界、生效时段冻结、改时/DST 无重复触发。
- Persistence：内存 Store 事务与回滚、临时 SQLite 重启恢复、Outbox 同事务。
- Notifications：授权/拒绝/后续关闭、旧 cycleID 回调无副作用、完成后清理通知。
- Overlay：真机矩阵——多屏、全屏 App、独立 Space、舞台管理器、热插拔、锁屏/唤醒。
- 每轮必须覆盖「完成、跳过、延后、暂停、自动完成」事件语义与幂等性。

## 里程碑

- M0（✅ 已完成）：风险验证（菜单栏、通知、全屏窗口、沙盒、空闲 API）+ Domain 内核 + 单提醒纵向闭环。
- M1（✅ 代码完成，真机验证清单待执行）：完整配置与多提醒、系统上下文、多屏与产品完整度。
- M2（进行中）：封闭测试加固、App Sandbox 接入与真机回归、签名/公证、上架审核预检、数据模型 v1 冻结。

## 非目标与边界

- 不做 iOS / watchOS / iCloud 同步、账号、服务端与遥测。
- 不做固定时间提醒、跨日多个生效时段、三级及以上升级工作流。
- 不索取辅助功能权限锁键鼠；不用摄像头/麦克风做动作识别。
- 视频会议/演示自动识别不在 MVP 范围，只提供手动暂停。

