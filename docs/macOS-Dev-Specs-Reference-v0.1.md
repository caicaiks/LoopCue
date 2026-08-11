# macOS 客户端开发规范文档速览

> LoopCue 开发团队参考手册：汇总 macOS 客户端开发相关的权威规范与优秀工程文档，并按项目模块标注优先级。
>
> 对应文档：《LoopCue PRD v0.1》《LoopCue 技术方案 v0.1》

| 项目 | 内容 |
| --- | --- |
| 文档版本 | v0.1 |
| 适用范围 | LoopCue macOS 客户端（Swift / SwiftUI / AppKit / Core Data） |
| 维护说明 | 外部规范以官方/上游为准，本文只做摘要与落地指引，不复制原文 |

---

## 1. 文档目的

LoopCue 是菜单栏常驻、依赖系统通知和多显示器全屏覆盖的 macOS 应用，恰好落在 macOS 平台最容易出问题的几个区域：

- 菜单栏常驻应用的正确形态（LSUIElement、状态栏图标、点击交互）。
- 本地通知的操作按钮、通知中心行为、勿扰模式边界。
- 全屏覆盖窗口的层级、Space 行为和审核边界。
- 沙盒、entitlements 与隐私权限的最小化。
- 无障碍（VoiceOver、键盘焦点、Reduce Motion）。

本文把「该读哪些规范、规范里管什么、什么时候用」整理成一张速览，避免团队成员各自去翻几十份官方文档。

---

## 2. 苹果官方规范（权威来源，属于规范本身）

### 2.1 Human Interface Guidelines（HIG）

- 网址：<https://developer.apple.com/design/human-interface-guidelines/>
- 定位：macOS 设计与交互的总纲，决定「系统级体验」是否符合平台惯例。
- 与 LoopCue 强相关的章节：
  - 菜单栏 / 菜单栏扩展（Menu Bar / Menu Bar Extras）：常驻应用的正确姿态。
  - 通知（Notifications）：操作按钮、通知中心行为、勿扰模式边界。
  - 窗口与全屏（Windows / Full Screen）：窗口层级、多 Space 行为。
  - 设置（Settings）：权限与设置页的组织方式。
- 使用时机：产品设计、交互评审、M0 UI 起点。

### 2.2 App Review Guidelines

- 网址：<https://developer.apple.com/app-store/review/guidelines/>
- 定位：上架审核规范，决定哪些 API、权限、文案与行为能通过审核。
- 与 LoopCue 相关：全屏强提醒的「可逃生性」、空闲检测不索取高风险权限、登录启动的透明说明、无账号产品的隐私页。
- 使用时机：进入 M2 封闭测试前，必须整体对照一遍。

### 2.3 App Sandbox Design Guide

- 网址：<https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/>
- 定位：沙盒与 entitlements 规范，定义应用可访问范围。
- 与 LoopCue 相关：LSUIElement 与沙盒共存、数据写入应用容器、不申请无关 entitlement。
- 使用时机：工程初始化（M0）即开启沙盒；M2 复核 entitlement 清单。

### 2.4 Swift API Design Guidelines

- 网址：<https://www.swift.org/documentation/api-design-guidelines/>
- 定位：Swift 命名与公共 API 风格规范，是代码评审的基准。
- 与 LoopCue 相关：Domain 层（Reminder、Cycle、Intent、Reducer）的命名一致性。
- 使用时机：日常编码与评审。

### 2.5 Accessibility（辅助功能）

- 网址：<https://developer.apple.com/documentation/accessibility>
- 定位：VoiceOver、键盘、动态类型、Reduce Motion 等无障碍能力规范。
- 与 LoopCue 相关：强提醒必须支持 VoiceOver、Tab 遍历、Escape 安全操作（PRD 6.4）。
- 使用时机：M1-C 无障碍检查、每次 UI 变更后。

### 2.6 App Programming Guide for macOS（归档）

- 网址：<https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/>
- 定位：早期但仍具参考价值的 macOS 架构指南：应用生命周期、事件循环、多显示器、窗口管理。
- 与 LoopCue 相关：理解 NSScreen / NSPanel / 会话与唤醒通知的行为边界。
- 注意：部分 API 已过时，以最新 Developer Documentation 为准。

---

## 3. 社区公认优秀的工程规范

### 3.1 Google Swift Style Guide

- 网址：<https://google.github.io/swift/>
- 最完整，常被团队直接采用；适合作为代码风格基线。

### 3.2 Ray Wenderlich Swift Style Guide

- 网址：<https://github.com/raywenderlich/swift-style-guide>
- 更贴近实际 App 工程，可读性好；适合快速对照。

### 3.3 GitHub Swift Style Guide

- 网址：<https://github.com/github/swift-style-guide>
- 简洁实用，适合作为团队内部规范的起点。

### 3.4 中文优质资源

- 王巍（onevcat）博客：Swift / macOS 工程实践讲解深入。
- objc.io：macOS 与 Swift 专题文章质量高。
- 定位：用于「原理与最佳实践」参考，不替代官方规范。

---

## 4. LoopCue 规范对照清单

按模块映射「该看哪份规范、规范管什么、验收要点」，直接挂到现有 PRD / 技术方案的对应章节。

| LoopCue 模块 | 对应规范 | 重点检查项 |
| --- | --- | --- |
| 菜单栏常驻（技术方案 5 / 13.1） | HIG Menu Bar | LSUIElement、状态栏图标、点击与右键交互、Dock 图标策略 |
| 弱提醒 / 通知（PRD F-04） | HIG Notifications | 操作按钮语义、通知清除不等于完成、勿扰模式边界 |
| 强提醒全屏（PRD F-05） | HIG Windows/Full Screen + Sandbox | 窗口层级、多 Space、可逃生性、不索要高权限 |
| 沙盒与权限（技术方案 16） | App Sandbox Design Guide + Review Guidelines | entitlement 最小化、数据容器、隐私页 |
| 无障碍（PRD 6.4 / 技术方案 11.4） | Apple Accessibility + HIG | VoiceOver、Tab 焦点、Reduce Motion |
| 代码风格（技术方案 5 工程结构） | Swift API Design + 3.x 风格指南 | Domain 命名、模块依赖方向、Review 基准 |
| 上架合规（PRD 18） | App Review Guidelines | 强提醒文案、登录启动说明、数据策略 |

---

## 5. 建议落地节奏

| 阶段 | 需要沉淀的规范动作 |
| --- | --- |
| M0 工程初始化 | 选 1 套 Swift 风格指南作为基线；按 HIG Menu Bar + Notifications 验证菜单栏与通知行为 |
| M0/M1 UI 实现 | 强提醒和设置页按 HIG Windows/Full Screen 与 Settings 对齐 |
| M1-C 打磨 | 按 Apple Accessibility 完成无障碍检查清单 |
| M2 封测前 | 整体过一遍 App Review Guidelines 和 Sandbox entitlement 清单 |
| 持续 | Swift API Design Guidelines 作为 Code Review 基准；外部规范更新时同步维护本文 |

---

## 6. 待办建议

- [ ] 从 3.1～3.3 中选定一套 Swift 风格指南，作为 LoopCue 代码评审基线。
- [ ] 将本文第 4 节检查项拆入各 Milestone 的验收清单。
- [ ] M2 前建立「上架审核预检清单」，覆盖强提醒可逃生性、权限说明与隐私页。
- [ ] 由团队约定是否另起一份内部《开发规范》，把命名、模块依赖、测试与提交要求固化为仓库文档。

