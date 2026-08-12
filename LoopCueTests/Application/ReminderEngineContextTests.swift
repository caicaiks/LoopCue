import XCTest
@testable import LoopCue

/// M1-B 系统上下文门控测试：暂停 / 离开 / 睡眠 / 锁屏 / 生效时段 / 启停。
///
/// 与 ReminderEngineTests 的区别：显式注入 FakeContextProvider 与
/// InMemoryAppStateStore，从而控制睡眠、锁屏、最后输入时刻等系统上下文。
final class ReminderEngineContextTests: XCTestCase {
    /// 周一 09:00（UTC），与 fixedCalendar 保持一致。
    private var t0: Date { date(2026, 8, 17, 9, 0, calendar: fixedCalendar()) }

    private func makeConfig(
        name: String = "测试",
        intervalMinutes: Int64 = 60,
        activeSchedule: ActiveSchedule = .alwaysOn,
        awayPolicy: AwayPolicy = .pause(threshold: .minutes(5))
    ) -> ReminderConfig {
        ReminderConfig(
            name: name,
            interval: .minutes(intervalMinutes),
            escalationDelay: .minutes(2),
            activeSchedule: activeSchedule,
            awayPolicy: awayPolicy
        )
    }

    private func makeEngine(
        store: CoreDataReminderStore,
        context: FakeContextProvider,
        appState: InMemoryAppStateStore
    ) -> ReminderEngine {
        context.context.calendar = fixedCalendar()
        return ReminderEngine(store: store, contextProvider: context, appState: appState)
    }

    private func activeElapsed(_ store: CoreDataReminderStore, _ id: UUID) -> Duration? {
        try? store.loadReminders().first(where: { $0.config.id == id })?.cycle?.activeElapsed
    }

    // MARK: - 暂停

    func testSingleTimedPauseFreezesAndExpiryDoesNotCountPausedTime() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let context = FakeContextProvider()
        let appState = InMemoryAppStateStore()
        let engine = makeEngine(store: store, context: context, appState: appState)
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)

        // 累计 10 分钟
        try await engine.reconcile(now: t0.addingTimeInterval(10 * 60))
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(10))

        // 暂停 30 分钟（到 9:40）
        try await engine.handle(.pauseReminder(config.id, .timed(.minutes(30))), now: t0.addingTimeInterval(10 * 60))
        // 暂停中推进 20 分钟（到 9:30）→ 不累计
        try await engine.reconcile(now: t0.addingTimeInterval(30 * 60))
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(10))

        // 推进到 9:50（暂停已到期）→ 只累计 9:40→9:50 的 10 分钟
        try await engine.reconcile(now: t0.addingTimeInterval(50 * 60))
        let stored = try store.loadReminders().first
        XCTAssertEqual(stored?.cycle?.activeElapsed, .minutes(20))
        XCTAssertNil(stored?.runtime.pauseUntil)
    }

    func testIndefinitePauseThenResumeRestartsFromResume() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let context = FakeContextProvider()
        let engine = makeEngine(store: store, context: context, appState: InMemoryAppStateStore())
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)

        try await engine.reconcile(now: t0.addingTimeInterval(10 * 60)) // +10
        try await engine.handle(.pauseReminder(config.id, .indefinite), now: t0.addingTimeInterval(10 * 60))
        try await engine.reconcile(now: t0.addingTimeInterval(30 * 60)) // 暂停中，仍 10
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(10))

        try await engine.handle(.resumeReminder(config.id), now: t0.addingTimeInterval(40 * 60))
        try await engine.reconcile(now: t0.addingTimeInterval(50 * 60)) // +10
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(20))
    }

    func testGlobalPauseFreezesAllAndResumeAllRestarts() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let context = FakeContextProvider()
        let engine = makeEngine(store: store, context: context, appState: InMemoryAppStateStore())
        let a = makeConfig(name: "A")
        let b = makeConfig(name: "B")
        try await engine.handle(.create(a), now: t0)
        try await engine.handle(.create(b), now: t0)

        try await engine.reconcile(now: t0.addingTimeInterval(10 * 60)) // 均 +10
        XCTAssertEqual(activeElapsed(store, a.id), .minutes(10))
        XCTAssertEqual(activeElapsed(store, b.id), .minutes(10))

        try await engine.handle(.pauseAll(.indefinite), now: t0.addingTimeInterval(10 * 60))
        try await engine.reconcile(now: t0.addingTimeInterval(30 * 60)) // 均暂停
        XCTAssertEqual(activeElapsed(store, a.id), .minutes(10))
        XCTAssertEqual(activeElapsed(store, b.id), .minutes(10))

        try await engine.handle(.resumeAll, now: t0.addingTimeInterval(40 * 60))
        try await engine.reconcile(now: t0.addingTimeInterval(50 * 60)) // 均 +10
        XCTAssertEqual(activeElapsed(store, a.id), .minutes(20))
        XCTAssertEqual(activeElapsed(store, b.id), .minutes(20))
    }

    func testGlobalTimedPauseExpiryClearsBannerAndDoesNotCountPause() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let context = FakeContextProvider()
        let appState = InMemoryAppStateStore()
        let engine = makeEngine(store: store, context: context, appState: appState)
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)

        try await engine.reconcile(now: t0.addingTimeInterval(10 * 60)) // +10
        try await engine.handle(.pauseAll(.timed(.minutes(10))), now: t0.addingTimeInterval(10 * 60))
        XCTAssertNotNil(appState.globalPauseUntil())

        try await engine.reconcile(now: t0.addingTimeInterval(15 * 60)) // 暂停中
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(10))

        try await engine.reconcile(now: t0.addingTimeInterval(25 * 60)) // 到期后 +5
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(15))
        XCTAssertNil(appState.globalPauseUntil())
    }

    func testPauseShownInSnapshot() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let context = FakeContextProvider()
        let engine = makeEngine(store: store, context: context, appState: InMemoryAppStateStore())
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)
        try await engine.handle(.pauseReminder(config.id, .indefinite), now: t0)

        let snapshot = AppSnapshot.make(from: try store.loadReminders(), now: t0)
        XCTAssertTrue(snapshot.reminders.first?.isPaused == true)
        XCTAssertEqual(snapshot.reminders.first?.pauseUntil, .distantFuture)

        try await engine.handle(.resumeReminder(config.id), now: t0.addingTimeInterval(60))
        let resumed = AppSnapshot.make(from: try store.loadReminders(), now: t0.addingTimeInterval(60))
        XCTAssertTrue(resumed.reminders.first?.isPaused == false)
        XCTAssertNil(resumed.reminders.first?.pauseUntil)
    }

    // MARK: - 离开

    func testAwayPauseCountsOnlyUpToBoundaryAndRestartsAfterReturn() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let context = FakeContextProvider()
        let engine = makeEngine(store: store, context: context, appState: InMemoryAppStateStore())
        // 离开策略：连续无输入 5 分钟暂停计时
        let config = makeConfig(awayPolicy: .pause(threshold: .minutes(5)))
        try await engine.handle(.create(config), now: t0)

        // 9:00 在场（默认最后输入为 distantFuture）
        try await engine.reconcile(now: t0)

        // 用户 9:30 最后输入，阈值 5 分钟 → 9:35 起离开
        context.context.lastInputAt = t0.addingTimeInterval(30 * 60)
        // 推进到 9:40 → 只累计到 9:35 = 35 分钟
        try await engine.reconcile(now: t0.addingTimeInterval(40 * 60))
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(35))

        // 9:50 回归，推进到 9:55 → 离开期（9:40→9:50）不累计，只累计 5 分钟
        context.context.lastInputAt = t0.addingTimeInterval(50 * 60)
        try await engine.reconcile(now: t0.addingTimeInterval(55 * 60))
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(40))
    }

    func testAwayAutoCompleteAfterObservedPresence() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let context = FakeContextProvider()
        let engine = makeEngine(store: store, context: context, appState: InMemoryAppStateStore())
        let config = makeConfig(name: "起身", awayPolicy: .complete(threshold: .minutes(3)))
        try await engine.handle(.create(config), now: t0)

        // 在场（默认最后输入为 distantFuture）→ 观察到在场
        try await engine.reconcile(now: t0)
        XCTAssertEqual(try store.loadReminders().first?.cycle?.hasObservedPresence, true)

        // 离开 5 分钟（阈值 3 分钟）
        context.context.lastInputAt = t0
        context.context.idleDuration = .minutes(5)
        try await engine.reconcile(now: t0.addingTimeInterval(5 * 60))

        let stored = try store.loadReminders().first
        XCTAssertEqual(stored?.cycle?.phase, .counting)
        XCTAssertEqual(stored?.cycle?.hasObservedPresence, false) // 新一轮
        XCTAssertEqual(try store.loadEvents(reminderID: config.id).map(\.type), [.autoCompleted])
    }

    func testAwayAutoCompleteRequiresObservedPresence() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let context = FakeContextProvider()
        let engine = makeEngine(store: store, context: context, appState: InMemoryAppStateStore())
        let config = makeConfig(name: "无人", awayPolicy: .complete(threshold: .minutes(3)))
        try await engine.handle(.create(config), now: t0)

        // 用户一小时前最后输入，从未观察到在场 → 不自动完成
        context.context.lastInputAt = t0.addingTimeInterval(-3600)
        context.context.idleDuration = .hours(1)
        try await engine.reconcile(now: t0.addingTimeInterval(5 * 60))

        let stored = try store.loadReminders().first
        XCTAssertEqual(stored?.cycle?.phase, .counting)
        XCTAssertEqual(stored?.cycle?.hasObservedPresence, false)
        XCTAssertTrue(try store.loadEvents(reminderID: config.id).isEmpty)
    }

    // MARK: - 睡眠 / 锁屏

    func testSleepWakeDoesNotCountSleepPeriod() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let context = FakeContextProvider()
        let engine = makeEngine(store: store, context: context, appState: InMemoryAppStateStore())
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)

        try await engine.reconcile(now: t0.addingTimeInterval(10 * 60)) // +10
        context.context.isAwake = false
        try await engine.reconcile(now: t0.addingTimeInterval(20 * 60)) // 睡眠中
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(10))

        context.context.isAwake = true
        try await engine.reconcile(now: t0.addingTimeInterval(30 * 60)) // 唤醒重开
        try await engine.reconcile(now: t0.addingTimeInterval(40 * 60)) // 唤醒后 +10
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(20))
    }

    func testLockUnlockDoesNotCountLockedPeriod() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let context = FakeContextProvider()
        let engine = makeEngine(store: store, context: context, appState: InMemoryAppStateStore())
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)

        try await engine.reconcile(now: t0.addingTimeInterval(10 * 60)) // +10
        context.context.isSessionActive = false
        try await engine.reconcile(now: t0.addingTimeInterval(20 * 60)) // 锁屏中
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(10))

        context.context.isSessionActive = true
        try await engine.reconcile(now: t0.addingTimeInterval(30 * 60)) // 解锁重开
        try await engine.reconcile(now: t0.addingTimeInterval(40 * 60)) // 解锁后 +10
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(20))
    }

    // MARK: - 生效时段

    func testScheduleGatingFreezesOutsideActiveWindow() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let context = FakeContextProvider()
        let engine = makeEngine(store: store, context: context, appState: InMemoryAppStateStore())
        // 生效时段 9:00-10:00（周一）
        let schedule = ActiveSchedule(weekdayMask: [1], startMinute: 9 * 60, endMinute: 10 * 60)
        let config = makeConfig(activeSchedule: schedule)
        try await engine.handle(.create(config), now: t0)

        // 9:00 → 10:30：只累计 9:00-10:00 = 60 分钟
        try await engine.reconcile(now: t0.addingTimeInterval(90 * 60))
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(60))

        // 10:30 → 11:00（仍在时段外）→ 不累计
        try await engine.reconcile(now: t0.addingTimeInterval(120 * 60))
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(60))
    }

    // MARK: - 启停

    func testDisableEnableDoesNotCountDisabledPeriod() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let context = FakeContextProvider()
        let engine = makeEngine(store: store, context: context, appState: InMemoryAppStateStore())
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)

        try await engine.reconcile(now: t0.addingTimeInterval(10 * 60)) // +10
        try await engine.handle(.setEnabled(config.id, false), now: t0.addingTimeInterval(10 * 60))
        // 禁用期间不 reconcile（引擎跳过），推进到 9:30 再启用
        try await engine.handle(.setEnabled(config.id, true), now: t0.addingTimeInterval(30 * 60))
        try await engine.reconcile(now: t0.addingTimeInterval(40 * 60)) // 启用后 +10
        XCTAssertEqual(activeElapsed(store, config.id), .minutes(20))
    }
}
