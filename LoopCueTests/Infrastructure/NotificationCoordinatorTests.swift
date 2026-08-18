import UserNotifications
import XCTest
@testable import LoopCue

final class NotificationCoordinatorTests: XCTestCase {
    private let reminderID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let cycleID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let effectID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!

    private func makeConfig(
        name: String = "喝水",
        message: String = "喝几口水",
        completionLabel: String = "已喝水",
        snoozeMinutes: Int64 = 15
    ) -> ReminderConfig {
        ReminderConfig(
            name: name,
            message: message,
            completionLabel: completionLabel,
            interval: .minutes(45),
            snoozeDuration: .minutes(Int64(snoozeMinutes))
        )
    }

    // MARK: - Category ID

    func testCategoryIDScopedByCompletionLabelAndSnooze() {
        let a = NotificationCategoryID.make(completionLabel: "已喝水", snoozeMinutes: 15)
        let b = NotificationCategoryID.make(completionLabel: "已喝水", snoozeMinutes: 10)
        let c = NotificationCategoryID.make(completionLabel: "已起身", snoozeMinutes: 15)
        let same = NotificationCategoryID.make(completionLabel: "已喝水", snoozeMinutes: 15)

        XCTAssertEqual(a, same)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Category 构建

    func testCategoriesDeduplicateSameLabelAndSnooze() {
        let configs = [
            makeConfig(),
            makeConfig(name: "另一个行动", completionLabel: "已喝水", snoozeMinutes: 15),
            makeConfig(completionLabel: "已起身", snoozeMinutes: 10),
        ]
        let categories = makeNotificationCategories(for: configs)
        XCTAssertEqual(categories.count, 2)
    }

    func testCategoryActionsUseConfigLabels() throws {
        let categories = makeNotificationCategories(for: [makeConfig()])
        let category = try XCTUnwrap(categories.first)
        let complete = try XCTUnwrap(
            category.actions.first { $0.identifier == NotificationActionID.complete }
        )
        let snooze = try XCTUnwrap(
            category.actions.first { $0.identifier == NotificationActionID.snooze }
        )
        XCTAssertEqual(complete.title, "已喝水")
        XCTAssertEqual(snooze.title, "15 分钟后提醒")
    }

    // MARK: - 通知内容

    func testNotificationContentUsesConfigValues() throws {
        let payload = NotificationContent(
            name: "喝水",
            message: "喝几口水，让自己缓一缓。",
            completionLabel: "已喝水",
            snoozeMinutes: 15
        )
        let content = NotificationContentBuilder.make(
            reminderID: reminderID,
            cycleID: cycleID,
            effectID: effectID,
            payload: payload
        )
        XCTAssertEqual(content.title, "喝水")
        XCTAssertEqual(content.body, "喝几口水，让自己缓一缓。")
        XCTAssertEqual(
            content.categoryIdentifier,
            NotificationCategoryID.make(completionLabel: "已喝水", snoozeMinutes: 15)
        )
        XCTAssertEqual(content.userInfo[NotificationUserInfoKey.reminderID] as? String, reminderID.uuidString)
        XCTAssertEqual(content.userInfo[NotificationUserInfoKey.cycleID] as? String, cycleID.uuidString)
        XCTAssertEqual(content.userInfo[NotificationUserInfoKey.effectID] as? String, effectID.uuidString)
        XCTAssertEqual(content.userInfo[NotificationUserInfoKey.schemaVersion] as? Int, NotificationSchemaVersion.current)
    }

    func testNotificationContentFallsBackWhenMessageEmpty() throws {
        let content = NotificationContentBuilder.make(
            reminderID: reminderID,
            cycleID: cycleID,
            effectID: effectID,
            payload: NotificationContent(name: "喝水", message: "", completionLabel: "已完成", snoozeMinutes: 10)
        )
        XCTAssertEqual(content.title, "喝水")
        XCTAssertEqual(content.body, "该行动需要你的回应")
    }

    // MARK: - 回调解析

    func testIntentParserReadsIdentityFromUserInfo() {
        let userInfo: [AnyHashable: Any] = [
            NotificationUserInfoKey.reminderID: reminderID.uuidString,
            NotificationUserInfoKey.cycleID: cycleID.uuidString,
            NotificationUserInfoKey.effectID: effectID.uuidString,
            NotificationUserInfoKey.schemaVersion: NotificationSchemaVersion.current,
        ]
        let identity = NotificationIntentParser.cycleIdentity(from: userInfo)
        XCTAssertEqual(identity?.reminderID, reminderID)
        XCTAssertEqual(identity?.cycleID, cycleID)
    }

    func testIntentParserReturnsNilForMalformedUserInfo() {
        XCTAssertNil(NotificationIntentParser.cycleIdentity(from: [:]))
        XCTAssertNil(NotificationIntentParser.cycleIdentity(from: [
            NotificationUserInfoKey.reminderID: "not-a-uuid",
            NotificationUserInfoKey.cycleID: cycleID.uuidString,
        ]))
    }

    func testIntentParserMapsActions() {
        let snooze = NotificationIntentParser.intent(
            actionIdentifier: NotificationActionID.snooze,
            reminderID: reminderID,
            cycleID: cycleID
        )
        XCTAssertEqual(snooze, .snooze(reminderID: reminderID, cycleID: cycleID))

        let completeButton = NotificationIntentParser.intent(
            actionIdentifier: NotificationActionID.complete,
            reminderID: reminderID,
            cycleID: cycleID
        )
        XCTAssertEqual(completeButton, .complete(reminderID: reminderID, cycleID: cycleID))

        // 点击通知正文（Default Action）→ 完成。
        let bodyTap = NotificationIntentParser.intent(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            reminderID: reminderID,
            cycleID: cycleID
        )
        XCTAssertEqual(bodyTap, .complete(reminderID: reminderID, cycleID: cycleID))
    }

    // MARK: - Effect Codable 兼容

    func testNewEffectEncodeDecodeRoundTrip() throws {
        let effect = ReminderEffect.sendWeakNotification(
            reminderID: reminderID,
            cycleID: cycleID,
            content: NotificationContent(
                name: "喝水",
                message: "喝几口水",
                completionLabel: "已喝水",
                snoozeMinutes: 15
            )
        )
        let data = try JSONEncoder().encode(effect)
        let decoded = try JSONDecoder().decode(ReminderEffect.self, from: data)
        XCTAssertEqual(decoded, effect)
    }

    func testLegacyEffectDecodeFallsBackToDefaultContent() throws {
        // 旧版本合成 Codable 格式：case 名为键，关联值标签为子键，
        // 且没有 content 字段 → 回退默认展示内容，不影响解码。
        let object: [String: Any] = [
            "sendWeakNotification": [
                "reminderID": reminderID.uuidString,
                "cycleID": cycleID.uuidString,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ReminderEffect.self, from: data)

        guard case .sendWeakNotification(let rid, let cid, let content) = decoded else {
            XCTFail("解码结果不是 sendWeakNotification")
            return
        }
        XCTAssertEqual(rid, reminderID)
        XCTAssertEqual(cid, cycleID)
        XCTAssertEqual(content, NotificationContent())
    }

    func testSubmissionPolicyAllowsOnlyAuthorizedOrProvisional() {
        XCTAssertTrue(NotificationSubmissionPolicy.isAllowed(.authorized))
        XCTAssertTrue(NotificationSubmissionPolicy.isAllowed(.provisional))
        XCTAssertFalse(NotificationSubmissionPolicy.isAllowed(.denied))
        XCTAssertFalse(NotificationSubmissionPolicy.isAllowed(.notDetermined))
    }

    func testSubmitResultDetailText() {
        XCTAssertEqual(
            NotificationSubmitResult.succeeded(alertEnabled: true).detail,
            "通知提交成功"
        )
        XCTAssertEqual(
            NotificationSubmitResult.succeeded(alertEnabled: false).detail,
            "已提交（横幅关闭，仅进通知中心）"
        )
        XCTAssertEqual(
            NotificationSubmitResult.skippedUnauthorized.detail,
            "未提交：通知权限未开启"
        )
        XCTAssertTrue(NotificationSubmitResult.failed("boom").isFailure)
        XCTAssertFalse(NotificationSubmitResult.succeeded(alertEnabled: true).isFailure)
    }
}
