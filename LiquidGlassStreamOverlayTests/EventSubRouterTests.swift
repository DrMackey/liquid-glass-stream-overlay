// EventSubRouterTests.swift
// Тесты маршрутизации типизированных событий в действия приложения

import Foundation
import Testing

@testable import Liquid_Glass_Stream_Overlay

@Suite("EventSub: роутер")
struct EventSubRouterTests {

    // MARK: - Сессия

    @Test("session_welcome превращается в подписку на типы событий")
    func welcomeRoutesToSubscribe() throws {
        let actions = EventSubRouter.actions(for: try EventSubFixtures.event(named: "session_welcome"))

        #expect(actions == [.subscribe(sessionId: "AQoQILE98gtqShGmLD7AM6yJThAB")])
    }

    @Test("session_reconnect превращается в переподключение по URL из сообщения")
    func reconnectRoutesToReconnect() throws {
        let actions = EventSubRouter.actions(for: try EventSubFixtures.event(named: "session_reconnect"))

        #expect(actions == [.reconnect(url: URL(string: "wss://eventsub.wss.twitch.tv?..."))])
    }

    @Test("session_reconnect без URL просит переподключиться к прежнему адресу")
    func reconnectWithoutURLFallsBack() throws {
        #expect(EventSubRouter.actions(for: .sessionReconnect(reconnectURL: nil)) == [.reconnect(url: nil)])
    }

    @Test("Нераспознанный reconnect_url не ломает переподключение", arguments: [
        "не адрес",
        "",
        "https://eventsub.wss.twitch.tv/ws",
        "wss://",
    ])
    func unparsableReconnectURLFallsBack(reconnectURL: String) throws {
        #expect(EventSubRouter.actions(for: .sessionReconnect(reconnectURL: reconnectURL)) == [.reconnect(url: nil)],
                "\(reconnectURL) не должен превращаться в адрес переподключения")
    }

    @Test("session_keepalive не требует действий")
    func keepaliveHasNoActions() throws {
        #expect(EventSubRouter.actions(for: try EventSubFixtures.event(named: "session_keepalive")).isEmpty)
    }

    @Test("Неизвестный message_type не требует действий")
    func unknownHasNoActions() throws {
        let event = EventSubEvent.unknown(messageType: "session_new_thing")

        #expect(EventSubRouter.actions(for: event).isEmpty)
    }

    @Test("revocation превращается в revoke с типом подписки")
    func revocationRoutesToRevoke() throws {
        let actions = EventSubRouter.actions(for: try EventSubFixtures.event(named: "revocation"))

        #expect(actions == [.revoke(subscriptionType: "channel.follow")])
    }

    // MARK: - Сообщения чата

    @Test("chat.message превращается в действие чата с полями события")
    func chatRoutesToChatAction() throws {
        let actions = EventSubRouter.actions(for: try EventSubFixtures.event(named: "notification_chat_message"))

        guard case .chat(let chat) = try #require(actions.first) else {
            Issue.record("Ожидалось действие .chat, получено \(actions)")
            return
        }
        #expect(actions.count == 1)
        #expect(chat.chatterUserName == "Streamer")
        #expect(chat.text == "hey chat! KappaLove")
        #expect(chat.colorHex == "#00FF7F")
        #expect(chat.badgePairs.count == 2)
    }

    // MARK: - Остальные подписки

    @Test("follow превращается в уведомление, а не в сообщение чата")
    func followRoutesToNotice() throws {
        let actions = EventSubRouter.actions(for: try EventSubFixtures.event(named: "notification_follow"))

        guard case .notice(let event) = try #require(actions.first) else {
            Issue.record("Ожидалось действие .notice, получено \(actions)")
            return
        }
        #expect(actions.count == 1)
        #expect(event.subscriptionType == "channel.follow")
        #expect(event.userName == "Awesome_User")
        #expect(event.messageId == "befa7b53-d79d-478f-86b9-120f112b044e")
    }

    @Test("redemption сохраняет заголовок награды в уведомлении")
    func redemptionRoutesToNotice() throws {
        let actions = EventSubRouter.actions(for: try EventSubFixtures.event(named: "notification_redemption"))

        guard case .notice(let event) = try #require(actions.first) else {
            Issue.record("Ожидалось действие .notice")
            return
        }
        #expect(event.title == "Обед в студии")
    }

    @Test("subscription.gift без title остаётся уведомлением без заголовка")
    func giftRoutesToNotice() throws {
        let actions = EventSubRouter.actions(for: try EventSubFixtures.event(named: "notification_subscription_gift"))

        guard case .notice(let event) = try #require(actions.first) else {
            Issue.record("Ожидалось действие .notice")
            return
        }
        #expect(event.title == nil)
        #expect(event.subscriptionType == "channel.subscription.gift")
    }

    // MARK: - Полнота покрытия

    @Test("Каждая фикстура маршрутизируется ровно одним действием или ни одним")
    func everyFixtureIsRouted() throws {
        let expected: [String: Int] = [
            "session_welcome": 1,
            "session_keepalive": 0,
            "session_reconnect": 1,
            "revocation": 1,
            "notification_follow": 1,
            "notification_chat_message": 1,
            "notification_redemption": 1,
            "notification_subscription_gift": 1,
        ]

        for (name, count) in expected {
            let actions = EventSubRouter.actions(for: try EventSubFixtures.event(named: name))
            #expect(actions.count == count, "Фикстура \(name): ожидалось \(count) действий")
        }
    }
}