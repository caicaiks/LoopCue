import XCTest
@testable import LoopCue

final class AppSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 3_000_000)

    private func makeConfig(
        id: UUID = UUID(),
        name: String,
        interval: Duration,
        escalationDelay: Duration? = nil,
        isEnabled: Bool = true
    ) -> ReminderConfig {
        ReminderConfig(
            id: id,
            name: name,
            interval: interval,
            escalationDelay: escalationDelay,
            isEnabled: isEnabled
        )
    }

    private func makeCycle(config: ReminderConfig) -> ReminderCycle {
        ReminderCycle(
            reminderID: config.id,
            policy: CyclePolicySnapshot(config: config),
            startedAt: now
        )
    }

    private func advance(
        _ config: ReminderConfig,
        by durations: Duration...
    ) -> ReminderCycle {
        var cycle = makeCycle(config: config)
        for duration in durations {
            cycle = ReminderReducer.advance(cycle, by: duration, now: now).cycle
        }
        return cycle
    }

    func testNextReminderIsEarliestCountingEnabled() {
        let a = makeConfig(name: "A", interval: .minutes(30))
        let b = makeConfig(name: "B", interval: .minutes(10))
        let disabled = makeConfig(name: "禁用", interval: .minutes(1), isEnabled: false)
        let stored = [
            StoredReminder(config: a, cycle: makeCycle(config: a)),
            StoredReminder(config: b, cycle: makeCycle(config: b)),
            StoredReminder(config: disabled, cycle: makeCycle(config: disabled)),
        ]

        let projection = AppSnapshot.project(stored, now: now)
        XCTAssertEqual(projection.next?.reminderID, b.id)
        XCTAssertEqual(projection.next?.remainingToWeak, .minutes(10))
    }

    func testNextReminderNilWhenAllWaitingOrNone() {
        let weak = makeConfig(name: "等待", interval: .minutes(5), escalationDelay: .minutes(2))
        let weakCycle = advance(weak, by: .minutes(5))
        XCTAssertEqual(weakCycle.phase, .weakPending)
        let projection = AppSnapshot.project(
            [StoredReminder(config: weak, cycle: weakCycle)],
            now: now
        )
        XCTAssertNil(projection.next)
        XCTAssertEqual(projection.pending.count, 1)
        XCTAssertEqual(projection.pending.first?.remainingToStrong, .minutes(2))
    }

    func testPendingCollectsWeakSnoozedStrong() {
        let weakConfig = makeConfig(name: "弱", interval: .minutes(5), escalationDelay: .minutes(2))
        let weakCycle = advance(weakConfig, by: .minutes(5))

        let snoozeConfig = makeConfig(name: "延后", interval: .minutes(5), escalationDelay: .minutes(2))
        var snoozeCycle = advance(snoozeConfig, by: .minutes(5))
        snoozeCycle = ReminderReducer.apply(
            .snooze(reminderID: snoozeConfig.id, cycleID: snoozeCycle.id),
            to: snoozeCycle,
            now: now
        ).cycle

        let strongConfig = makeConfig(name: "强", interval: .minutes(5), escalationDelay: .minutes(2))
        let strongCycle = advance(strongConfig, by: .minutes(5), .minutes(2))

        let stored = [
            StoredReminder(config: weakConfig, cycle: weakCycle),
            StoredReminder(config: snoozeConfig, cycle: snoozeCycle),
            StoredReminder(config: strongConfig, cycle: strongCycle),
        ]
        let projection = AppSnapshot.project(stored, now: now)

        XCTAssertEqual(projection.pending.count, 3)
        XCTAssertEqual(projection.strong.count, 1)
        XCTAssertEqual(projection.strong.first?.reminderID, strongConfig.id)
        XCTAssertEqual(projection.strong.first?.message, strongConfig.message)
    }

    func testStrongQueueOrdersByTriggeredThenCreated() {
        let early = makeConfig(name: "早", interval: .minutes(5), escalationDelay: .minutes(1))
        let late = makeConfig(name: "晚", interval: .minutes(5), escalationDelay: .minutes(2))
        let earlyCycle = advance(early, by: .minutes(5), .minutes(1))
        let lateCycle = advance(late, by: .minutes(5), .minutes(2))
        XCTAssertEqual(earlyCycle.phase, .strongPending)
        XCTAssertEqual(lateCycle.phase, .strongPending)

        // 反转输入顺序，验证排序不依赖插入顺序（按 strongTriggeredAt 升序）。
        let projection = AppSnapshot.project(
            [StoredReminder(config: late, cycle: lateCycle), StoredReminder(config: early, cycle: earlyCycle)],
            now: now
        )
        XCTAssertEqual(projection.strong.map(\.reminderID), [early.id, late.id])
    }

    func testSnapshotMakeBuildsProjections() {
        let config = makeConfig(name: "列表", interval: .minutes(5), escalationDelay: .minutes(2))
        let weakCycle = advance(config, by: .minutes(5))
        let snapshot = AppSnapshot.make(
            from: [StoredReminder(config: config, cycle: weakCycle)],
            now: now
        )
        XCTAssertEqual(snapshot.reminders.count, 1)
        XCTAssertNil(snapshot.nextReminder)
        XCTAssertEqual(snapshot.pendingResponses.count, 1)
    }

    func testStrongQueueCarriesActionFields() {
        var config = makeConfig(name: "强", interval: .minutes(5), escalationDelay: .minutes(2))
        config.maxSnoozeCount = 3
        let strongCycle = advance(config, by: .minutes(5), .minutes(2))
        let projection = AppSnapshot.project(
            [StoredReminder(config: config, cycle: strongCycle)],
            now: now
        )
        XCTAssertEqual(projection.strong.count, 1)
        let item = try? XCTUnwrap(projection.strong.first)
        XCTAssertEqual(item?.snoozeCount, 0)
        XCTAssertEqual(item?.maxSnoozeCount, 3)
        XCTAssertEqual(item?.snoozeDuration, .minutes(10))
        XCTAssertEqual(item?.displayScope, .all)
    }

    func testStrongQueueExcludesSuppressedCycleButPendingKeepsIt() {
        let config = makeConfig(name: "强", interval: .minutes(5), escalationDelay: .minutes(2))
        let strongCycle = advance(config, by: .minutes(5), .minutes(2))
        XCTAssertEqual(strongCycle.phase, .strongPending)

        // Escape / 暂时关闭 → 进入 5 分钟抑制期，覆盖队列不应再展示。
        let suppressed = ReminderReducer.apply(
            .dismissOverlay(reminderID: config.id, cycleID: strongCycle.id),
            to: strongCycle,
            now: now
        ).cycle
        XCTAssertEqual(suppressed.overlaySuppressionRemaining, .minutes(5))

        let projection = AppSnapshot.project(
            [StoredReminder(config: config, cycle: suppressed)],
            now: now
        )
        // 覆盖队列排除，但菜单栏「等待回应」仍保留，抑制剩余用于倒计时展示。
        XCTAssertTrue(projection.strong.isEmpty)
        XCTAssertEqual(projection.pending.count, 1)
        XCTAssertEqual(projection.pending.first?.remainingToStrong, .minutes(5))
    }
}
