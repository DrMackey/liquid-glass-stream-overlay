// EventSubNotificationDecoderTests.swift
// Проверки типизированного разбора payload'ов подписок

import Testing
import Foundation
@testable import Liquid_Glass_Stream_Overlay

@Suite("EventSub: типизированный разбор подписок")
struct EventSubNotificationDecoderTests {

    // MARK: - Все подключённые типы

    /// Минимальные валидные payload'ы для каждой подписки из `desiredTypes`.
    private static let cases: [(type: String, kind: SubscriptionKind, event: String, userName: String?, title: String?)] = [
        ("channel.channel_points_custom_reward_redemption.add", .channelPointsRewardRedemption,
         #"{"user_name":"Cool_Viewer","reward":{"title":"Обед в студии"}}"#, "Cool_Viewer", "Обед в студии"),
        ("channel.chat.clear", .chatClear,
         "{}", nil, nil),
        ("channel.chat.clear_user_messages", .chatClearUserMessages,
         #"{"target_user_name":"Spammer"}"#, "Spammer", nil),
        ("channel.chat.message_delete", .chatMessageDelete,
         #"{"target_user_name":"Spammer"}"#, "Spammer", nil),
        ("channel.chat.notification", .chatNotification,
         #"{"chatter_user_name":"Moderator","message":{"text":"Опрос начинается"}}"#, "Moderator", "Опрос начинается"),
        ("channel.follow", .follow,
         #"{"user_name":"Awesome_User"}"#, "Awesome_User", nil),
        ("channel.subscribe", .subscribe,
         #"{"user_name":"Awesome_User","tier":"1000"}"#, "Awesome_User", nil),
        ("channel.subscription.end", .subscriptionEnd,
         #"{"user_name":"Awesome_User","tier":"1000"}"#, "Awesome_User", nil),
        ("channel.subscription.gift", .subscriptionGift,
         #"{"user_name":"Generous_Gifter","total":5,"tier":"1000"}"#, "Generous_Gifter", nil),
        ("channel.subscription.message", .subscriptionMessage,
         #"{"user_name":"Loyal_User","cumulative_months":6}"#, "Loyal_User", nil),
        ("channel.raid", .raid,
         #"{"from_broadcaster_user_name":"Raider","to_broadcaster_user_name":"Streamer","viewers":42}"#, "Raider", nil),
        ("channel.goal.progress", .goalProgress,
         #"{"goal":{"title":"1000 отжиманий","is_achieved":false,"current_amount":10,"target_amount":1000},"progress":1.0}"#, nil, "1000 отжиманий"),
        ("channel.goal.end", .goalEnd,
         #"{"goal":{"title":"1000 отжиманий","is_achieved":true,"current_amount":1000,"target_amount":1000},"ended_at":"2024-01-01T00:00:00Z"}"#, nil, "1000 отжиманий"),
        ("channel.update", .streamUpdate,
         #"{"title":"Новое название стрима","category_name":"Just Chatting"}"#, nil, "Новое название стрима"),
        ("channel.ban", .ban,
         #"{"user_name":"Spammer","moderator_user_name":"Moderator","reason":"спам"}"#, "Spammer", nil),
        ("channel.unban", .unban,
         #"{"user_name":"Spammer","moderator_user_name":"Moderator"}"#, "Spammer", nil),
        ("channel.vip.add", .vipAdd,
         #"{"user_name":"Regular_VIP"}"#, "Regular_VIP", nil),
        ("channel.vip.remove", .vipRemove,
         #"{"user_name":"Regular_VIP"}"#, "Regular_VIP", nil),
        ("channel.hype_train.begin", .hypeTrainBegin,
         #"{"total":1,"progress":0,"goal":1800}"#, nil, nil),
        ("channel.hype_train.progress", .hypeTrainProgress,
         #"{"total":5,"progress":null,"goal":1800}"#, nil, nil),
        ("channel.hype_train.end", .hypeTrainEnd,
         #"{"total":10,"progress":null,"goal":null}"#, nil, nil),
    ]

    @Test("Каждая подписка из desiredTypes разбирается в свою проекцию", arguments: cases)
    func eachSubscriptionDecodes(case testCase: (type: String, kind: SubscriptionKind, event: String, userName: String?, title: String?)) throws {
        let data = Self.makeNotification(type: testCase.type, event: testCase.event)

        guard case .notification(let payload) = try JSONDecoder().decode(EventSubEvent.self, from: data),
              case .event(let notice) = payload else {
            Issue.record("Ожидался event payload для \(testCase.type)")
            return
        }

        #expect(notice.kind == testCase.kind)
        #expect(notice.subscriptionType == testCase.type)
        #expect(notice.userName == testCase.userName)
        #expect(notice.title == testCase.title)
        #expect(notice.messageId == "mid-\(testCase.type)")
    }

    @Test("SubscriptionKind разбирает и отдаёт настоящие строки Twitch")
    func subscriptionKindMatchesTwitchStrings() throws {
        let types = Self.cases.map(\.type) + ["channel.chat.message"]

        for type in types {
            #expect(SubscriptionKind.parse(type).rawValue == type, "\(type) не совпадает со своей строкой Twitch")
        }
    }

    @Test("Каждый запрашиваемый тип подписки известен декодеру")
    func everyDesiredTypeIsKnown() throws {
        // Тип, о котором декодер не знает, тихо превратился бы в `.unsupported`,
        // и событие перестало бы появляться в интерфейсе без всякой ошибки.
        let unknown = TwitchChatManager.desiredEventSubTypes.filter {
            if case .other = SubscriptionKind.parse($0) { return true }
            return false
        }

        #expect(unknown.isEmpty, "Эти подписки не разбираются: \(unknown)")
    }

    @Test("Декодер покрывает все типы, которые приложение просит у Twitch")
    func decoderCoversEveryDesiredType() throws {
        // Проверяем не только список, но и сам разбор: на каждый запрашиваемый
        // тип приходится либо `.chat`, либо `.event`.
        for type in TwitchChatManager.desiredEventSubTypes {
            let event: String
            if type == "channel.chat.message" {
                event = #"{"chatter_user_name":"V","message":{"text":"hi"},"badges":[]}"#
            } else {
                event = Self.minimalEvents[type] ?? "{}"
            }

            let data = Self.makeNotification(type: type, event: event)
            guard case .notification(let payload) = try JSONDecoder().decode(EventSubEvent.self, from: data) else {
                Issue.record("\(type) не дал notification payload")
                continue
            }
            switch payload {
            case .chat, .event:
                break
            case .unsupported:
                Issue.record("\(type) разобрался как unsupported")
            }
        }
    }

    // MARK: - Сообщения чата

    @Test("channel.chat.message остаётся отдельным payload'ом чата")
    func chatMessageKeepsChatPayload() throws {
        let data = Self.makeNotification(
            type: "channel.chat.message",
            event: ##"{"chatter_user_name":"Viewer","message":{"text":"Привет"},"badges":[],"color":"#FF0000"}"##
        )

        guard case .notification(let payload) = try JSONDecoder().decode(EventSubEvent.self, from: data),
              case .chat(let chat) = payload else {
            Issue.record("Ожидался chat payload")
            return
        }
        #expect(chat.chatterUserName == "Viewer")
        #expect(chat.text == "Привет")
        #expect(chat.rawColorHex == "#FF0000")
    }

    // MARK: - Строгость разбора

    @Test("Обязательные поля проверяются", arguments: [
        ("channel.follow", #"{}"#),
        ("channel.subscribe", #"{"user_name":"User"}"#),
        ("channel.raid", #"{"from_broadcaster_user_name":"A","to_broadcaster_user_name":"B"}"#),
        ("channel.goal.progress", #"{"goal":{},"progress":1.0}"#),
        ("channel.goal.end", #"{"goal":{},"ended_at":"2024-01-01T00:00:00Z"}"#),
        ("channel.chat.notification", #"{"chatter_user_name":"Mod"}"#),
        ("channel.update", "{}"),
        ("channel.chat.clear_user_messages", "{}"),
    ])
    func missingRequiredFieldFails(subscriptionType: String, event: String) {
        let data = Self.makeNotification(type: subscriptionType, event: event)
        #expect(throws: (any Error).self, "\(subscriptionType) должен требовать свои поля") {
            try JSONDecoder().decode(EventSubEvent.self, from: data)
        }
    }

    @Test("Анонимный подарок разбирается без user_name")
    func anonymousGiftDecodes() throws {
        let data = Self.makeNotification(
            type: "channel.subscription.gift",
            event: #"{"total":1,"tier":"1000","is_anonymous":true}"#
        )

        guard case .notification(let payload) = try JSONDecoder().decode(EventSubEvent.self, from: data),
              case .event(let notice) = payload else {
            Issue.record("Ожидался event payload")
            return
        }
        #expect(notice.userName == nil)
        #expect(notice.title == nil)
    }

    @Test("Пустой текст подарка-сообщения остаётся пустым заголовком")
    func emptyGiftMessageYieldsEmptyTitle() throws {
        let data = Self.makeNotification(
            type: "channel.subscription.message",
            event: #"{"user_name":"User","cumulative_months":1,"message_text":""}"#
        )

        guard case .notification(let payload) = try JSONDecoder().decode(EventSubEvent.self, from: data),
              case .event(let notice) = payload else {
            Issue.record("Ожидался event payload")
            return
        }
        #expect(notice.title == "")
    }

    // MARK: - Неизвестные типы

    @Test("Неизвестная подписка принимается, но не интерпретируется", arguments: [
        "channel.something.brand_new",
        "channel.automod.message.hold",
    ])
    func unknownSubscriptionIsUnsupported(subscriptionType: String) throws {
        // Payload намеренно бессмысленный: разбор event'а пропускается.
        let data = Self.makeNotification(type: subscriptionType, event: #"{"totally":"unrelated"}"#)

        guard case .notification(let payload) = try JSONDecoder().decode(EventSubEvent.self, from: data),
              case .unsupported(let type) = payload else {
            Issue.record("Ожидался unsupported payload для \(subscriptionType)")
            return
        }
        #expect(type == subscriptionType)
    }

    @Test("Отсутствующий subscription_type не превращается в уведомление")
    func missingSubscriptionTypeIsUnsupported() throws {
        let json = """
        {
          "metadata": { "message_type": "notification" },
          "payload": { "event": { "user_name": "Someone" } }
        }
        """

        guard case .notification(let payload) = try JSONDecoder().decode(
            EventSubEvent.self, from: Data(json.utf8)
        ), case .unsupported(let type) = payload else {
            Issue.record("Ожидался unsupported payload")
            return
        }
        #expect(type == "")
    }

    // MARK: - Маршрутизация

    @Test("Уведомление и сообщение чата расходятся по маршрутам")
    func routesDifferPerPayload() throws {
        let follow = try JSONDecoder().decode(
            EventSubEvent.self,
            from: Self.makeNotification(type: "channel.follow", event: #"{"user_name":"User"}"#)
        )
        #expect(EventSubRouter.actions(for: follow) == [.notice(EventSubNotice(
            kind: .follow,
            subscriptionType: "channel.follow",
            messageId: "mid-channel.follow",
            userName: "User"
        ))])

        let unsupported = try JSONDecoder().decode(
            EventSubEvent.self,
            from: Self.makeNotification(type: "channel.new.thing", event: "{}")
        )
        #expect(EventSubRouter.actions(for: unsupported).isEmpty)
    }

    // MARK: - Хелперы

    /// Минимальные валидные payload'ы из `cases`, собранные в словарь.
    private static var minimalEvents: [String: String] {
        Dictionary(uniqueKeysWithValues: cases.map { ($0.type, $0.event) })
    }

    private static func makeNotification(type: String, event: String) -> Data {
        Data("""
        {
          "metadata": {
            "message_id": "mid-\(type)",
            "message_type": "notification",
            "subscription_type": "\(type)"
          },
          "payload": { "event": \(event) }
        }
        """.utf8)
    }
}