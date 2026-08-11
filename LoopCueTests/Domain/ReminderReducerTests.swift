import XCTest
@testable import LoopCue

final class ReminderReducerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private var policy: CyclePolicySnapshot!

    override func setUpWithError() throws {
        let config = ReminderConfig(
            name: "测试",
            interval: .minutes(5),
            escalationDelay: .minutes(2),
            snoozeDuration: .minutes(10),
            maxSnoozeCount: 2,
            awayPolicy: .complete(threshold: .minutes(3))
        )
        policy = CyclePolicySnapshot(config: config)
    }

    private func makeCycle() -> ReminderCycle {
        ReminderCycle(reminderID: UUID(), policy: policy, startedAt: now)
    }

    private func reminderID(of cycle: ReminderCycle) -> UUID { cycle.reminderID }
    private func cycleID(of cycle: ReminderCycle) -> UUID { cycle.id }

    private func containsEffect(
        _ effects: [ReminderEffect],
        _ match: (ReminderEffect) -> Bool
    ) -> Bool {
        effects.contains(where: match)
    }

    // MARK: - 时间推进

    func testCountingCrossesWeakThresholdExactly() {
        let result = ReminderReducer.advance(makeCycle(), by: .minutes(5), now: now)
        XCTAssertEqual(result.cycle.phase, .weakPending)
        XCTAssertEqual(result.events.map(\.type), [.weakTriggered])
        XCTAssertTrue(containsEffect(result.effects) {
            if case .sendWeakNotification = $0 { return true }
            return false
        })
    }

    func testLargeDeltaCrossesWeakThenStrong() {
        let result = ReminderReducer.advance(makeCycle(), by: .minutes(7), now: now)
        XCTAssertEqual(result.cycle.phase, .strongPending)
        XCTAssertEqual(result.events.map(\.type), [.weakTriggered, .strongTriggered])
        XCTAssertTrue(containsEffect(result.effects) {
            if case .presentStrongOverlay = $0 { return true }
            return false
        })
    }

    func testIgnoredNotificationDoesNotChangePhase() {
        let weak = ReminderReducer.advance(makeCycle(), by: .minutes(5), now: now).cycle
        // 升级等待 2 分钟，只推进 1 分钟 → 仍等待弱提醒回执，无新事件
        let result = ReminderReducer.advance(weak, by: .minutes(1), now: now)
        XCTAssertEqual(result.cycle.phase, .weakPending)
        XCTAssertTrue(result.events.isEmpty)
    }

    func testWithoutEscalationPhaseStaysWeakPending() {
        var config = ReminderConfig(name: "测试", interval: .minutes(5), escalationDelay: nil)
        let noEscalationPolicy = CyclePolicySnapshot(config: config)
        let cycle = ReminderCycle(reminderID: UUID(), policy: noEscalationPolicy, startedAt: now)
        let weak = ReminderReducer.advance(cycle, by: .minutes(5), now: now).cycle
        let result = ReminderReducer.advance(weak, by: .hours(1), now: now)
        XCTAssertEqual(result.cycle.phase, .weakPending)
        XCTAssertTrue(result.events.isEmpty)
    }

    func testZeroDeltaDoesNotChangeState() {
        let cycle = makeCycle()
        let result = ReminderReducer.advance(cycle, by: .zero, now: now)
        XCTAssertEqual(result.cycle, cycle)
        XCTAssertTrue(result.events.isEmpty)
        XCTAssertTrue(result.effects.isEmpty)
    }

    // MARK: - 延后

    func testSnoozeFreezesEscalationAndRepeatsWeakWhenExpired() {
        let weak = ReminderReducer.advance(makeCycle(), by: .minutes(5), now: now).cycle
        let snoozed = ReminderReducer.apply(
            .snooze(reminderID: reminderID(of: weak), cycleID: cycleID(of: weak)),
            to: weak,
            now: now
        ).cycle

        XCTAssertEqual(snoozed.phase, .snoozed)
        XCTAssertEqual(snoozed.snoozeCount, 1)
        XCTAssertEqual(snoozed.escalationElapsed, .zero)

        // 延后期间推进时间：不消耗升级计时
        let during = ReminderReducer.advance(snoozed, by: .minutes(1), now: now).cycle
        XCTAssertEqual(during.phase, .snoozed)
        XCTAssertEqual(during.escalationElapsed, .zero)

        // 延后到期 → 回到 WeakPending 并重复弱提醒，升级计时仍冻结
        let expired = ReminderReducer.advance(snoozed, by: .minutes(10), now: now).cycle
        XCTAssertEqual(expired.phase, .weakPending)
        XCTAssertEqual(expired.escalationElapsed, .zero)
        XCTAssertNil(expired.snoozeRemaining)
    }

    func testSnoozeCountLimitBlocksFurtherSnooze() {
        let weak = ReminderReducer.advance(makeCycle(), by: .minutes(5), now: now).cycle

        let first = ReminderReducer.apply(
            .snooze(reminderID: reminderID(of: weak), cycleID: cycleID(of: weak)),
            to: weak,
            now: now
        )
        let second = ReminderReducer.apply(
            .snooze(reminderID: reminderID(of: first.cycle), cycleID: cycleID(of: first.cycle)),
            to: first.cycle,
            now: now
        )
        XCTAssertEqual(second.cycle.snoozeCount, 2)

        let third = ReminderReducer.apply(
            .snooze(reminderID: reminderID(of: second.cycle), cycleID: cycleID(of: second.cycle)),
            to: second.cycle,
            now: now
        )
        XCTAssertEqual(third.cycle.snoozeCount, 2)
        XCTAssertTrue(third.events.isEmpty)
        XCTAssertTrue(third.effects.isEmpty)
    }

    func testSnoozeNotAllowedInCountingPhase() {
        let cycle = makeCycle()
        let result = ReminderReducer.apply(
            .snooze(reminderID: reminderID(of: cycle), cycleID: cycleID(of: cycle)),
            to: cycle,
            now: now
        )
        XCTAssertEqual(result.cycle, cycle)
        XCTAssertTrue(result.events.isEmpty)
    }

    // MARK: - 回执

    func testCompleteSkipAndAutoCompleteCreateDifferentEvents() {
        let completedCycle = ReminderReducer.advance(makeCycle(), by: .minutes(5), now: now).cycle
        let completed = ReminderReducer.apply(
            .complete(reminderID: reminderID(of: completedCycle), cycleID: cycleID(of: completedCycle)),
            to: completedCycle,
            now: now
        )
        XCTAssertEqual(completed.events.map(\.type), [.completed])
        XCTAssertNotEqual(completed.cycle.id, completedCycle.id)

        let skippedCycle = ReminderReducer.advance(makeCycle(), by: .minutes(5), now: now).cycle
        let skipped = ReminderReducer.apply(
            .skip(reminderID: reminderID(of: skippedCycle), cycleID: cycleID(of: skippedCycle)),
            to: skippedCycle,
            now: now
        )
        XCTAssertEqual(skipped.events.map(\.type), [.skipped])

        let observed = ReminderReducer.noteUserActivity(makeCycle())
        let auto = ReminderReducer.applyIdle(observed, idleDuration: .minutes(5), now: now)
        XCTAssertEqual(auto.events.map(\.type), [.autoCompleted])
    }

    func testStaleCycleIDHasNoSideEffects() {
        let cycle = makeCycle()
        let completed = ReminderReducer.apply(
            .complete(reminderID: reminderID(of: cycle), cycleID: cycleID(of: cycle)),
            to: cycle,
            now: now
        )
        // 用旧 cycleID 对已完成后的新轮执行操作 → 无副作用
        let stale = ReminderReducer.apply(
            .complete(reminderID: reminderID(of: cycle), cycleID: cycleID(of: cycle)),
            to: completed.cycle,
            now: now
        )
        XCTAssertEqual(stale.cycle, completed.cycle)
        XCTAssertTrue(stale.events.isEmpty)
        XCTAssertTrue(stale.effects.isEmpty)
    }

    func testCompleteWithWrongReminderIDIsIgnored() {
        let cycle = makeCycle()
        let result = ReminderReducer.apply(
            .complete(reminderID: UUID(), cycleID: cycleID(of: cycle)),
            to: cycle,
            now: now
        )
        XCTAssertEqual(result.cycle, cycle)
        XCTAssertTrue(result.events.isEmpty)
    }

    func testTriggerWeakNowImmediatelyEntersWeakPending() {
        let cycle = makeCycle()
        let result = ReminderReducer.apply(
            .triggerWeakNow(reminderID: reminderID(of: cycle), cycleID: cycleID(of: cycle)),
            to: cycle,
            now: now
        )
        XCTAssertEqual(result.cycle.phase, .weakPending)
        XCTAssertEqual(result.events.map(\.type), [.weakTriggered])
    }

    // MARK: - 强提醒关闭与重现

    func testDismissOverlayKeepsStrongPendingAndReappears() {
        let strong = ReminderReducer.advance(makeCycle(), by: .minutes(7), now: now).cycle
        XCTAssertEqual(strong.phase, .strongPending)

        let dismissed = ReminderReducer.apply(
            .dismissOverlay(reminderID: reminderID(of: strong), cycleID: cycleID(of: strong)),
            to: strong,
            now: now
        )
        XCTAssertEqual(dismissed.cycle.phase, .strongPending)
        XCTAssertEqual(dismissed.cycle.overlaySuppressionRemaining, .minutes(5))
        XCTAssertEqual(dismissed.events.map(\.type), [.overlayDismissed])

        // 隐藏 4 分钟：仍处于隐藏状态
        let stillHidden = ReminderReducer.advance(dismissed.cycle, by: .minutes(4), now: now).cycle
        XCTAssertEqual(stillHidden.phase, .strongPending)
        XCTAssertNotNil(stillHidden.overlaySuppressionRemaining)

        // 累计满 5 分钟：重新展示
        let reappeared = ReminderReducer.advance(dismissed.cycle, by: .minutes(5), now: now)
        XCTAssertEqual(reappeared.cycle.phase, .strongPending)
        XCTAssertNil(reappeared.cycle.overlaySuppressionRemaining)
        XCTAssertTrue(reappeared.events.contains { $0.type == .strongRepeated })
        XCTAssertTrue(containsEffect(reappeared.effects) {
            if case .presentStrongOverlay = $0 { return true }
            return false
        })
    }

    // MARK: - 离开自动完成

    func testAwayCompleteRequiresObservedPresence() {
        let cycle = makeCycle()

        // 未观察到在场 → 不自动完成
        let noPresence = ReminderReducer.applyIdle(cycle, idleDuration: .minutes(10), now: now)
        XCTAssertTrue(noPresence.events.isEmpty)
        XCTAssertEqual(noPresence.cycle, cycle)

        // 观察到在场后离开达到阈值 → 自动完成
        let observed = ReminderReducer.noteUserActivity(cycle)
        XCTAssertTrue(observed.hasObservedPresence)
        let auto = ReminderReducer.applyIdle(observed, idleDuration: .minutes(5), now: now)
        XCTAssertEqual(auto.events.map(\.type), [.autoCompleted])
        XCTAssertNotEqual(auto.cycle.id, observed.id)

        // 离开未达阈值 → 不自动完成
        let below = ReminderReducer.applyIdle(observed, idleDuration: .minutes(1), now: now)
        XCTAssertTrue(below.events.isEmpty)
    }

    func testPauseAwayPolicyNeverAutoCompletes() {
        let pauseConfig = ReminderConfig(
            name: "喝水",
            interval: .minutes(45),
            escalationDelay: .minutes(15),
            awayPolicy: .pause(threshold: .minutes(5))
        )
        let cycle = ReminderCycle(
            reminderID: UUID(),
            policy: CyclePolicySnapshot(config: pauseConfig),
            startedAt: now
        )
        let observed = ReminderReducer.noteUserActivity(cycle)
        let result = ReminderReducer.applyIdle(observed, idleDuration: .hours(1), now: now)
        XCTAssertTrue(result.events.isEmpty)
        XCTAssertEqual(result.cycle, observed)
    }
}

