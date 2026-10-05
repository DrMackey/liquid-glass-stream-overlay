// EventSubEventTests.swift
// Тесты типизированного декодирования сообщений EventSub

import Foundation
import Testing

@testable import Liquid_Glass_Stream_Overlay

@Suite("EventSub: декодирование событий")
struct EventSubEventTests {

    // MARK: - Сессия

    @Test("session_welcome даёт id сессии")
    func welcomeCarriesSessionId() throws {
        let event = try EventSubFixtures.event(named: "session_welcome")

        guard case .sessionWelcome(let id) = event else {
            Issue.record("Ожидался sessionWelcome, получено \(event)")
            return
        }
        #expect(id == "AQoQILE98gtqShGmLD7AM6yJThAB")
    }

    @Test("session_keepalive разбирается без payload")
    func keepaliveDecodes() throws {
        let event = try EventSubFixtures.event(named: "session_keepalive")

        guard case .sessionKeepalive = event else {
            Issue.record("Ожидался sessionKeepalive, получено \(event)")
            return
        }
    }

    @Test("session_reconnect содержит reconnect_url")
    func reconnectCarriesURL() throws {
        let event = try EventSubFixtures.event(named: "session_reconnect")

        guard case .sessionReconnect(let url) = event else {
            Issue.record("Ожидался sessionReconnect, получено \(event)")
            return
        }
        #expect(url == "wss://eventsub.wss.twitch.tv?...")
    }

    @Test("revocation даёт тип отозванной подписки")
    func revocationCarriesSubscriptionType() throws {
        let event = try EventSubFixtures.event(named: "revocation")

        guard case .revocation(let type) = event else {
            Issue.record("Ожидался revocation, получено \(event)")
            return
        }
        #expect(type == "channel.follow")
    }

    // MARK: - Сообщения чата

    @Test("chat.message извлекает отправителя, текст, цвет и бейджи")
    func chatMessageExtractsFields() throws {
        let event = try EventSubFixtures.event(named: "notification_chat_message")

        guard case .notification(let payload) = event, case .chat(let chat) = payload else {
            Issue.record("Ожидался chat payload, получено \(event)")
            return
        }
        #expect(chat.chatterUserName == "Streamer")
        #expect(chat.text == "hey chat! KappaLove")
        #expect(chat.colorHex == "#00FF7F")
        #expect(chat.badges == [
            ChatMessageEvent.Badge(set_id: "subscriber", id: "1"),
            ChatMessageEvent.Badge(set_id: "moderator", id: "1"),
        ])
    }

    @Test("Пустой color в chat.message становится nil, а не пустой строкой")
    func emptyColorBecomesNil() throws {
        let payload = try decodeChat(overridingEvent: ["color": ""])

        #expect(payload.colorHex == nil)
    }

    @Test("Отсутствующий color в chat.message даёт nil")
    func missingColorBecomesNil() throws {
        let payload = try decodeChat(overridingEvent: ["color": nil])

        #expect(payload.colorHex == nil)
    }

    @Test("chat.message без обязательного chatter_user_name не декодируется")
    func chatMessageWithoutChatterFails() throws {
        let event = try decodeRawChat(overridingEvent: ["chatter_user_name": nil])

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(EventSubEvent.self, from: event)
        }
    }

    @Test("chat.message без текста не декодируется")
    func chatMessageWithoutTextFails() throws {
        let event = try decodeRawChat(overridingEvent: ["message": ["text": nil]])

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(EventSubEvent.self, from: event)
        }
    }

    @Test("Бейдж без set_id или id отбрасывается")
    func malformedBadgeIsDropped() throws {
        let payload = try decodeChat(overridingEvent: [
            "badges": [["set_id": "subscriber"], ["id": "1"]]
        ])

        #expect(payload.badges.isEmpty)
    }

    // MARK: - Остальные подписки

    @Test("follow достаёт user_name и message_id из metadata")
    func followDecodesNotice() throws {
        let event = try EventSubFixtures.event(named: "notification_follow")

        guard case .notification(let payload) = event, case .event(let notice) = payload else {
            Issue.record("Ожидался event payload, получено \(event)")
            return
        }
        #expect(notice.kind == .follow)
        #expect(notice.subscriptionType == "channel.follow")
        #expect(notice.userName == "Awesome_User")
        #expect(notice.messageId == "befa7b53-d79d-478f-86b9-120f112b044e")
        #expect(notice.title == nil)
    }

    @Test("redemption берёт title из reward")
    func redemptionTakesRewardTitle() throws {
        let event = try EventSubFixtures.event(named: "notification_redemption")

        guard case .notification(let payload) = event, case .event(let notice) = payload else {
            Issue.record("Ожидался event payload, получено \(event)")
            return
        }
        #expect(notice.kind == .channelPointsRewardRedemption)
        #expect(notice.title == "Обед в студии")
        #expect(notice.userName == "Cool_Viewer")
    }

    @Test("subscription.gift без title даёт nil, а не пустую строку")
    func giftWithoutTitleYieldsNil() throws {
        let event = try EventSubFixtures.event(named: "notification_subscription_gift")

        guard case .notification(let payload) = event, case .event(let notice) = payload else {
            Issue.record("Ожидался event payload, получено \(event)")
            return
        }
        #expect(notice.kind == .subscriptionGift)
        #expect(notice.title == nil)
        #expect(notice.userName == "Generous_Gifter")
    }

    @Test("Пустой title трактуется как отсутствие заголовка")
    func emptyTitleYieldsRawFallback() throws {
        let event = try decodeNotification(
            subscriptionType: "channel.update",
            overridingEvent: ["title": ""]
        )
        guard case .notification(let payload) = try JSONDecoder().decode(EventSubEvent.self, from: event),
              case .event(let notice) = payload else {
            Issue.record("Ожидался event payload")
            return
        }

        #expect(notice.title == "")
        #expect(notice.subscriptionType == "channel.update")
    }

    @Test("Неизвестный subscription_type не превращается в уведомление")
    func unknownSubscriptionTypeIsUnsupported() throws {
        let json = """
        {
          "metadata": { "message_type": "notification", "subscription_type": "channel.something.new" },
          "payload": { "event": { "user_name": "Someone" } }
        }
        """

        guard case .notification(let payload) = try JSONDecoder().decode(
            EventSubEvent.self, from: Data(json.utf8)
        ), case .unsupported(let subscriptionType) = payload else {
            Issue.record("Ожидался unsupported payload")
            return
        }
        #expect(subscriptionType == "channel.something.new")
    }

    @Test("Все фикстуры декодируются одним проходом")
    func allFixturesDecode() throws {
        let names = [
            "session_welcome", "session_keepalive", "session_reconnect", "revocation",
            "notification_follow", "notification_chat_message",
            "notification_redemption", "notification_subscription_gift",
        ]

        for name in names {
            let data = try EventSubFixtures.data(named: name)
            #expect(throws: Never.self, "Фикстура \(name) не должна падать при декодировании") {
                try JSONDecoder().decode(EventSubEvent.self, from: data)
            }
        }
    }

    // MARK: - Ошибки декодирования

    @Test("Битый JSON не декодируется")
    func malformedJSONFails() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(EventSubEvent.self, from: Data("{не json".utf8))
        }
    }

    @Test("Пустой JSON не декодируется — message_type обязателен")
    func emptyObjectFails() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(EventSubEvent.self, from: Data("{}".utf8))
        }
    }

    @Test("session_welcome без session.id не декодируется")
    func welcomeWithoutSessionIdFails() {
        let json = """
        { "metadata": { "message_type": "session_welcome" }, "payload": { "session": {} } }
        """

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(EventSubEvent.self, from: Data(json.utf8))
        }
    }

    @Test("Неизвестный message_type не считается ошибкой")
    func unknownMessageTypeIsNotAnError() throws {
        let json = """
        { "metadata": { "message_type": "session_something_new" } }
        """

        guard case .unknown(let type) = try JSONDecoder().decode(EventSubEvent.self, from: Data(json.utf8)) else {
            Issue.record("Ожидался unknown")
            return
        }
        #expect(type == "session_something_new")
    }

    @Test("notification без payload не декодируется")
    func notificationWithoutPayloadFails() {
        let json = """
        { "metadata": { "message_type": "notification", "subscription_type": "channel.follow" } }
        """

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(EventSubEvent.self, from: Data(json.utf8))
        }
    }

    // MARK: - Хелперы

    /// Декодирует фикстуру чата, подменяя значения в `payload.event`.
    private func decodeChat(overridingEvent overrides: [String: Any?]) throws -> ChatMessageEvent {
        let event = try decodeRawChat(overridingEvent: overrides)

        guard case .notification(let payload) = try JSONDecoder().decode(EventSubEvent.self, from: event),
              case .chat(let chat) = payload else {
            Issue.record("Ожидался chat payload")
            throw FixtureError.expectedChat
        }
        return chat
    }

    private func decodeRawChat(overridingEvent overrides: [String: Any?]) throws -> Data {
        var json = try EventSubFixtures.json(named: "notification_chat_message") as! [String: Any]
        var payload = json["payload"] as! [String: Any]
        var event = payload["event"] as! [String: Any]

        for (key, value) in overrides {
            if let value { event[key] = value } else { event.removeValue(forKey: key) }
        }

        payload["event"] = event
        json["payload"] = payload
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// Строит уведомление с произвольным payload'ом: ключи в overrides
    /// заменяются существующие, nil — удаляются.
    private func decodeNotification(subscriptionType: String, overridingEvent overrides: [String: Any?]) throws -> Data {
        let json = """
        {
          "metadata": {
            "message_id": "mid-1",
            "message_type": "notification",
            "subscription_type": "\(subscriptionType)"
          },
          "payload": { "event": { "user_name": "Someone", "title": "Stream title" } }
        }
        """
        var root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        var payload = root["payload"] as! [String: Any]
        var event = payload["event"] as! [String: Any]

        for (key, value) in overrides {
            if let value { event[key] = value } else { event.removeValue(forKey: key) }
        }

        payload["event"] = event
        root["payload"] = payload
        return try JSONSerialization.data(withJSONObject: root)
    }

    enum FixtureError: Error {
        case expectedChat
    }
}