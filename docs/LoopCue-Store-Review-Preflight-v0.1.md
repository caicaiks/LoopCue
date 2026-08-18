# LoopCue 上架审核预检清单

> 面向 Mac App Store / 公证发布的审核预检。进入 M2 封闭测试前整体对照一遍；
> 对应《App Review Guidelines》与《App Sandbox Design Guide》。

| 项目 | 内容 |
| --- | --- |
| 文档版本 | v0.1 |
| 适用范围 | LoopCue macOS 客户端（macOS 13+） |
| 对应文档 | PRD v0.1 §18、技术方案 v0.1 §16、macOS-Dev-Specs-Reference §2.2/2.3 |
| 维护说明 | 发布前逐项勾选；涉及审核行为的改动需回填 |

---

## 1. 可逃生性与强提醒合规

PRD 与技术方案红线：强提醒是可关闭的全屏覆盖，不是不可绕过的锁定。

| # | 检查项 | 现状 | 状态 |
| --- | --- | --- | --- |
| 1.1 | 强提醒始终提供 Escape（暂时关闭）安全出口 | `StrongReminderView` 绑定 `.cancelAction` | ☐ |
| 1.2 | 提供可见的「暂时关闭」按钮（不止快捷键） | 卡片内显式按钮 | ☐ |
| 1.3 | 不模拟系统登录窗口、不索取辅助功能权限锁键鼠 | 未申请辅助功能 | ☐ |
| 1.4 | 允许用户退出应用 / Cmd+Tab / Force Quit 等系统级逃生 | 未拦截系统快捷键 | ☐ |
| 1.5 | 文案避免「强制锁定/无法退出」类承诺 | 文案统一为「全屏强提醒」 | ☐ |

## 2. 权限最小化

技术方案 §16.1 权限清单：

| # | 能力 | 是否需要授权 | 现状核对 | 状态 |
| --- | --- | --- | --- | --- |
| 2.1 | 通知（弱提醒 + 操作按钮） | 是，创建首个提醒后申请 | `requestAuthorization([.alert, .sound])`；首启延后申请（Onboarding） | ☐ |
| 2.2 | 登录时启动 | 显式开关 | `SMAppService`，菜单栏/设置页开关 | ☐ |
| 2.3 | 辅助功能 | 否 | 未申请 | ☐ |
| 2.4 | 输入监听 | 否 | 仅读取系统聚合空闲时长（`secondsSinceLastEventType`） | ☐ |
| 2.5 | 摄像头 / 麦克风 | 否 | 未申请 | ☐ |
| 2.6 | 网络 | 否 | 无网络 entitlement，无服务端依赖 | ☐ |

## 3. 沙盒与 entitlements

| # | 检查项 | 现状 | 状态 |
| --- | --- | --- | --- |
| 3.1 | App Sandbox 已开启 | `ENABLE_APP_SANDBOX=YES`（Xcode 16+ 构建设置注入） | ☐ |
| 3.2 | entitlements 保持最小 | `LoopCue.entitlements` 最小空字典，由 Xcode 管理 | ☐ |
| 3.3 | Debug / Release 产物均嵌入 sandbox | `codesign -d --entitlements` 验证 | ☐ |
| 3.4 | 数据写入应用容器 | Core Data 使用 `~/Library/Containers/.../Data`（Application Support） | ☐ |
| 3.5 | 无无关 entitlement（网络/文件/Apple Events） | 不申请 | ☐ |

## 4. 隐私与数据策略

| # | 检查项 | 现状 | 状态 |
| --- | --- | --- | --- |
| 4.1 | 全部数据本地存储，无账号、无网络 | PRD §12；MVP 无服务端 | ☐ |
| 4.2 | 空闲检测不记录输入内容/位置 | 只读聚合时长 | ☐ |
| 4.3 | 日志不记录提醒正文、完成文案、用户输入 | 按技术方案 §17 审计（engine/scheduler/persistence/activity/notification/overlay/app） | ☐ |
| 4.4 | 提供「删除所有本地数据」入口 | 设置页，二次确认后清空 | ☐ |
| 4.5 | 隐私政策说明（如发布 App Store） | 待补充对外文案 | ☐ |

## 5. 功能与体验完整性

| # | 检查项 | 现状 | 状态 |
| --- | --- | --- | --- |
| 5.1 | 核心闭环完整：创建 → 弱提醒 → 升级 → 完成重置 | M1-C 完成，117 单测覆盖 | ☐ |
| 5.2 | 通知权限异常有清晰修复入口 | 设置页深链 + 菜单栏状态 | ☐ |
| 5.3 | 登录启动说明「退出后提醒不运行」 | 菜单栏/Onboarding 文案 | ☐ |
| 5.4 | 无障碍基础：VoiceOver、Tab 遍历、Escape | 强提醒卡片；完成按钮默认焦点（FocusState） | ☐ |

## 6. 发布前待决策项（PRD §18 / 技术方案 §23）

| # | 决策项 | 建议 | 状态 |
| --- | --- | --- | --- |
| 6.1 | 品牌名「叮刻 LoopCue」与商标/域名/商店名可用性 | 发布前核查 | ☐ |
| 6.2 | 最低系统 macOS 13 还是 14 | 当前按 13（Core Data） | ☐ |
| 6.3 | 强提醒默认覆盖所有/当前显示器 | 当前默认 all | ☐ |
| 6.4 | 定价策略（免费/买断/Pro） | MVP 建议免费 | ☐ |
| 6.5 | 起身模板「离开 3 分钟自动完成」默认开启 | 封测观察误判率后定 | ☐ |
| 6.6 | 首发渠道：仅 Mac App Store 或同时官网公证 | 决定签名/公证/更新方案 | ☐ |

## 7. 发布物料清单

- [ ] 应用图标（16/32/128/256/512/1024pt）
- [ ] 截图与预览（多屏强提醒、菜单栏、列表、设置）
- [ ] 隐私政策链接
- [ ] 支持 URL / 反馈渠道
- [ ] 版本说明（Release Notes）
- [ ] 内容分级信息

---

## 8. 签名与公证

| # | 检查项 | 现状 | 状态 |
| --- | --- | --- | --- |
| 8.1 | Debug/Release 自动签名（Apple Development） | team `V3VLU2P2MZ` 已配置 | ☐ |
| 8.2 | 分发签名（Developer ID / App Store） | 待 M2 换证书 | ☐ |
| 8.3 | 公证（notarization） | 待 M2 | ☐ |
| 8.4 | Hardened Runtime | `ENABLE_HARDENED_RUNTIME=YES` | ☐ |
