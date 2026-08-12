# LoopCue 开发进展记录

> 记录里程碑完成状态、最近改动、验证结果与待办。随开发持续更新。

| 项目 | 内容 |
| --- | --- |
| 文档版本 | v0.1 |
| 最近更新 | 2026-08-12 |
| 对应文档 | PRD v0.1、技术方案 v0.1、AGENTS.md |
| 当前分支 | `feat/init` |

## 1. 里程碑总览

| 里程碑 | 状态 | 说明 |
| --- | --- | --- |
| M0-A 风险验证 | ✅ | 菜单栏、通知、全屏窗口、沙盒、空闲 API |
| M0-B 领域内核 | ✅ | Reducer 状态机 + 配置校验 |
| M0-C 单提醒纵向闭环 | ✅ | Engine / Core Data / Outbox / EffectDispatcher / Overlay |
| M1-A 完整配置与多提醒 | ✅ | 四模板、列表/编辑/启停/删除、下一轮/立即生效 |
| M1-B 系统上下文 | ✅ | 生效时段、睡眠/锁屏/闲置/离开、单项与全局暂停、登录启动 |
| M1-C 多屏与产品完整度 | 🚧 进行中 | **Step 1（Overlay）、Step 2（设置页/删除清理/通知）已完成**；Step 3 待做 |
| M2 封闭测试加固 | ⬜ | 未开始 |

单元测试：**103 个全部通过**（10 个测试类）。Debug / Release 构建均通过（Release 需关闭代码签名或使用开发者证书）。

## 2. 最近改动（2026-08-12，M1-C Step 2）

### 3.1 改动清单

| Commit | 内容 | 涉及文件 |
| --- | --- | --- |
| `afe22f7` | feat(M1-C)：设置页、删除清理与动态通知 Category | 19 个文件，+1029/-84 |

### 2.2 Step 2 实现内容

- **设置页 `Features/Settings`**（PRD 9.2 / 10.4）：通知权限状态与「打开系统设置」修复入口（`x-apple.systempreferences` 深链 + 失败回退系统设置首页）、新建提醒默认覆盖显示器（`AppSettingsStore` 存 UserDefaults）、默认离开阈值（1/3/5/10/15/30/60 分钟，策略固定暂停计时）、登录启动（复用 `LoginItemManager`）、删除所有本地数据（二次确认 + 清空全部通知）；Debug 专属「清空数据并重新开始」从菜单栏移入设置页（`#if DEBUG`，Release 排除）。
- **删除提醒级联清理**（技术方案 9.2）：`ReminderEngine.handle(.delete)` 级联删除提醒、全部 Event 与属于该提醒的 Outbox 效果（`deleteReminderCascade`，效果按解码出的 reminderID 匹配），并补发 `clearNotifications + dismissStrongOverlay` 清理效果。
- **通知内容与动态 Category**（PRD F-04 / 6.3 / 技术方案 10.2/10.3）：`ReminderEffect.sendWeakNotification` 携带自包含 `NotificationContent`（标题=行动名、正文=`config.message`、完成文案、延后分钟数），由 Engine 落盘 Outbox 时从配置富化；Category ID 按 `completionLabel + snoozeMinutes` 生成，动作标题动态（完成=自定义文案，延后=「N 分钟后提醒」）；`userInfo` 补 `effectID` 与 `schemaVersion`（`EffectExecutor.execute` 增加 effectID 参数）；完成按钮 / 点击正文均走 complete，延后按钮走 snooze。
- **Category 注册时机**：新增 `NotificationCategoryRegistrar`，由 AppModel 快照转发驱动，仅在 (completionLabel, snoozeMinutes) 组合集合变化时重新注册，避免每秒快照刷新造成无谓的 `setNotificationCategories` 调用；启动、增删改后自动收敛。
- **向后兼容**：`ReminderEffect` 改为手工 Codable，兼容旧版本合成格式（case 名为键、关联值标签为子键），缺失 `content` 时回退默认展示内容。

### 2.3 关键架构决策与发现

1. **通知内容在落盘时富化，Reducer 保持纯语义**：`ReminderReducer` 只发 `sendWeakNotification(reminderID, cycleID)`（占位内容），Engine 在 `persist` 时用当时配置填充 `NotificationContent`。领域层不依赖展示字段，而持久化 Effect 自包含：发送不依赖运行期查询，旧轮次通知不受后续编辑影响。
2. **动态 Category 集合按签名增量注册**：把「启动一次性注册」改为快照驱动 + 签名去重，配置增删改后自动收敛，且不引入每秒 `setNotificationCategories` 的开销。
3. **自定义 Enum Codable 兼容旧格式**：合成 Codable 对带关联值的 enum 使用「case 名作为键、关联值标签作为子键」的结构（本机实测确认）。`ReminderEffect` 手工实现新旧两种格式解码，`content` 缺失时回退默认值，防止旧 Outbox 数据升级后解码失败。

### 2.4 验证结果

- ✅ 103 个单元测试通过（新增 17 个：通知 Category/内容/userInfo/回调解析 10 个、AppSettingsStore 3 个、Engine 删除级联与内容富化 3 个、Store 级联删除 1 个）。
- ✅ Debug / Release 构建通过。
- ⚠️ 真机交互验证（动态 Category 按钮文案、通知权限修复入口、删除后通知清理、设置页各项）**待用户人工测试**，见第 6 节清单。

### 2.5 测试期间的环境观察

- 通知授权请求在此环境返回 `UNErrorDomain Code=1`（未知），不影响计时与强提醒；真机需确认权限流程与动态 Category 稳定性（技术方案 10.2 已知风险：不稳定则降级通用「已完成/稍后提醒」文案）。
- 空闲门控：StandUp 模板 `awayPolicy = .complete(threshold: 3min)`，键鼠无输入超过 3 分钟即停止累计有效时长，真机验证需保持输入活跃。

## 3. 最近改动（2026-08-12，M1-C Step 1）

### 2.1 改动清单

| Commit | 内容 | 涉及文件 |
| --- | --- | --- |
| `0d24e8a` | feat(M1-C)：强提醒多卡队列、数据驱动卡片、多屏热插拔 | 12 个文件，+367/-63 |
| `6f3bd18` | fix：CyclePolicySnapshot 旧数据缺 `displayScope` 导致启动失败 | 2 个文件，+45 |

### 3.2 Step 1 实现内容

- **Overlay 多卡队列**（PRD F-05 / 技术方案 11.3）：`OverlayPresenter` 由 AppSnapshot 驱动，同一时刻只展示 `strongQueue` 主卡片（排序：`strongTriggeredAt` → `createdAt` → UUID 兜底）；完成/跳过后原地切换下一项；其余项显示「还有 N 项等待回应」。
- **数据驱动强提醒卡片**（PRD 6.4 / 10.3）：`StrongReminderView` 展示行动名、提醒文案、自定义完成按钮文案（如「已起身」）、「这项行动已经等待 X 分钟」；新增「N 分钟后提醒（延后）」与「跳过本次」按钮；Escape /「暂时关闭」仍走 `dismissOverlay`（5 分钟抑制期）。
- **多屏与热插拔**（技术方案 11.2）：新增 `DisplayScope` 配置字段（`all` / `current`，PRD 默认 `all`）+ 编辑页选择器；监听 `didChangeScreenParametersNotification`，显示器变化时重建/校正窗口，不写业务状态。
- **抑制期语义**：Escape 后轮次仍为 `strongPending` 但带 `overlaySuppressionRemaining`；`AppSnapshot.project` 将其排除出覆盖队列（5 分钟有效时长后经 `strongRepeated` 再现），菜单栏「等待回应」仍显示并展示「已暂时关闭 · N 分钟后再次提醒」。
- **无障碍**：纯系统控件 + 纯文本，`accessibilityLabel/Hint`，完成按钮为 `.defaultAction`、暂时关闭为 `.cancelAction`（Escape），无动画兼容 Reduce Motion。

### 3.3 关键架构决策与发现

1. **AsyncStream 非广播流**：实测两个迭代器会分流元素（t1 收 `[0,2,3,4]`、t2 只收 `[1]`）。因此 `engine.snapshots` 必须保持单一消费者（AppModel），其它 MainActor 消费者（OverlayPresenter）通过 `AppModel.onSnapshotUpdate` 回调转发，避免快照丢失。
2. **Codable 向后兼容必须手工处理**：新增持久化字段（如 `displayScope`）时，若依赖合成 Codable 严格解码，旧数据会直接抛 `keyNotFound` 导致启动失败（本次踩坑：`CyclePolicySnapshot`）。新增字段一律用 `decodeIfPresent ?? 默认值` 手工解码（参考 `ReminderConfig.activeSchedule` 先例）。
3. **Overlay 展示由快照驱动而非 Effect 驱动**：`present/dismiss` Effect 保留为 Outbox 信号（幂等触发重渲染），但实际展示内容以 Engine 发布的快照为唯一数据源，保证队列切换、抑制期、重启恢复语义一致。

### 3.4 验证结果

- ✅ 86 个单元测试通过（新增 3 个：强提醒快照字段、抑制期队列排除、displayScope 旧数据回退；修复后追加 1 个：旧 cycle 缺 displayScope 解码回归）。
- ✅ Debug / Release 构建通过。
- ✅ 应用启动冒烟：修复前菜单栏永久「加载中」（崩溃根因见 2.3.2）；修复后正常初始化。
- ⚠️ 真机交互验证（多卡队列、延后/跳过、多屏热插拔、仅当前显示器、VoiceOver）**待用户人工测试**，见第 6 节清单。

### 3.5 测试期间的环境观察

- 通知授权请求在此环境返回 `UNErrorDomain Code=1`（未知），不影响计时与强提醒；真机需确认权限流程。
- 空闲门控：StandUp 模板 `awayPolicy = .complete(threshold: 3min)`，键鼠无输入超过 3 分钟即停止累计有效时长，真机验证需保持输入活跃。

## 4. 已知问题与风险

| 问题 | 影响 | 状态 |
| --- | --- | --- |
| `ReminderSnapshot.remainingToWeak` 使用 `config.interval` 而非 `cycle.policy.interval` | 编辑「下一轮生效」后列表剩余时间按新周期误算 | 待修（Step 3） |
| 菜单栏缺「立即提醒一次」入口（`triggerWeakNow` Intent 已有） | PRD 6.5 功能缺失 | 待做（Step 3） |
| Scheduler 1 秒轮询且每次 reconcile 写 checkpoint | 每秒写 Core Data，违反技术方案 18 能耗预算 | 待做（Step 3） |
| 无 Onboarding 引导，启动即自动创建模板并申请权限 | PRD 6.1 | 待做（Step 3） |
| 重启恢复模式未启用（当前每次启动重新计时） | 产品决策，技术方案 13.1 恢复逻辑保留在 `start(now:)` | M2 前确认 |
| 本机无开发者证书，Release 需 `CODE_SIGNING_ALLOWED=NO` | 上架/公证前需配置签名 | M2 |
| CoreDataReminderStore `perform` 存在 Swift 6 Sendable 警告（历史遗留） | 仅警告，不影响运行 | 待清理 |
| 动态 Category 稳定性未真机确认 | 自定义完成文案可能随系统限制失效 | 真机验证；不稳定则降级通用文案 |

## 5. 待办计划

### Step 2 — 设置页 + 删除清理 + 通知完善（约 1 周）

- [x] 设置页 `Features/Settings`：通知权限状态与「打开系统设置」修复入口、默认覆盖显示器、默认离开阈值、删除所有本地数据（二次确认）、登录启动（复用 `LoginItemManager`）；菜单栏 Debug 性质「清空数据并重新开始」挪入设置页或 DEBUG 编译排除。
- [x] `ReminderEngine.handle(.delete)` 追加 `clearNotifications + dismissStrongOverlay` 效果（同事务 Outbox）。
- [x] 通知内容使用 `config.message`；动态 Category 按 `completionLabel` 注册（技术方案 10.2，真机确认稳定性，不稳定则降级通用文案）；`userInfo` 补 `schemaVersion` / `effectID`。
- [x] 通知相关单元测试（内容构建、动态 Category、userInfo、回调解析、旧 cycleID 幂等、删除清理）；授权/拒绝/后续关闭等真机集成测试见第 6 节清单。

### Step 3 — Onboarding + Scheduler 优化（约 3～4 天）

- [ ] 首次启动引导流（说明 → 模板选择 → 通知权限申请延后到创建首个提醒时）。
- [ ] Scheduler 重构：按下一事件点唤醒（弱提醒/延后结束/强提醒/生效时段边界/暂停截止/抑制结束）+ 30 秒轻量 checkpoint + 系统上下文事件驱动 reconcile；UI 倒计时独立 1 秒展示，不触发写库。
- [ ] 修复 `ReminderSnapshot.remainingToWeak` 使用 policy 快照；菜单栏加「立即提醒一次」。

### Step 4 — M2 前加固

- [ ] Overlay 真机矩阵（多屏、全屏 App、Space、舞台管理器、热插拔、锁屏/唤醒）记录。
- [ ] 产品决策确认（技术方案 23）：重启恢复模式、起身自动完成默认值、最低系统版本、首发渠道。
- [ ] 日志审计（不记提醒正文/用户输入）、无障碍走查、性能（空闲 CPU、常驻内存 < 80MB）。
- [ ] 签名 / 公证 / App Sandbox 检查、数据模型冻结与 migration fixture。

## 6. 真机验证清单（待用户执行）

### M1-C Step 1

1. **多卡队列**：创建两个短周期提醒（如 5 分钟 + 升级 1 分钟），同时升级后 Overlay 只显示一张主卡片 + 「还有 1 项等待回应」，完成后自动切到下一项，最后一项结束后全部关闭。
2. **延后 / 跳过 / 暂时关闭**：主卡片按钮文案与行为正确；Escape 生效，5 分钟（有效时长）后再现。
3. **多屏**：外接屏时每屏一个窗口；热插拔后窗口自动重建；任一屏点完成全部关闭且只记一条事件。
4. **仅当前显示器**：编辑页设置「全屏强提醒覆盖 = 仅当前显示器」，验证只盖鼠标所在屏。
5. **无障碍**：Tab 遍历按钮（完成 → 延后 → 跳过 → 暂时关闭），VoiceOver 朗读行动名与状态。

### M1-C Step 2

1. **动态 Category**：弱提醒通知的完成按钮显示自定义文案（如「已喝水」）、延后按钮显示「N 分钟后提醒」；点击正文直接完成。
2. **通知权限修复入口**：拒绝通知后打开设置页，看到异常状态与「打开系统设置」，点击后能跳转到系统通知设置；重新开启后菜单栏/设置页状态恢复。
3. **删除提醒清理**：删除正在等待回应或已送达通知的提醒后，通知中心不再显示该提醒的通知；若正在全屏覆盖，删除后窗口立即关闭。
4. **删除所有本地数据**：设置页删除后回到「暂无提醒」，系统通知中心无残留通知；重启后按当前逻辑重新创建默认模板。
5. **设置默认值**：修改「默认覆盖显示器 / 默认离开阈值」后新建提醒，编辑器初始值与设置一致；已有提醒不受影响。
6. **登录启动**：设置页开关与菜单栏开关行为一致，首次开启若需系统确认，按提示完成。

## 7. 构建与测试环境说明

```bash
# 首次准备
brew install xcodegen          # 工程生成工具（已装）
sudo xcode-select -s /Applications/Xcode.app   # 切换完整 Xcode

# 常用命令（详见 Makefile）
make generate   # project.yml -> LoopCue.xcodeproj
make test       # 全部单元测试（103 个）
make build      # Debug 构建
make run        # 构建并启动（菜单栏）
```

- 本机无开发者证书：构建需 `CODE_SIGNING_ALLOWED=NO`，或先在 Xcode 配置签名（`DEVELOPMENT_TEAM=627M2GD4Q9`）。
- Debug 时间倍率 10 倍速（起身 30 分钟 ≈ 3 分钟弱提醒 / 6 分钟强提醒），Release 恒为真实时间；该倍率经 `#if DEBUG` 排除在 Release 之外。
- 每次启动重新计时（`freshStart`）：保留配置，重置轮次与 Outbox，不清空历史事件表结构（事件与效果被清空）。
- 测试运行器需连接 `testmanagerd`，必须在沙盒外终端执行；若出现 `Early unexpected exit`，先 `pkill -x LoopCue; pkill -x xctest` 再重试。
