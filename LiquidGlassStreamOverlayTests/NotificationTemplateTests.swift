// NotificationTemplateTests.swift
// Проверки шаблонов уведомлений и подстановки значений

import Testing
import Foundation
import SwiftUI
@testable import Liquid_Glass_Stream_Overlay

@Suite("Уведомления: шаблоны и подстановка")
struct NotificationTemplateTests {

    // MARK: - Набор шаблонов

    @Test("Шаблоны заданы для всего списка интересующих событий")
    func defaultTemplatesExistForNotificationKinds() {
        let kinds: [SubscriptionKind] = [
            .channelPointsRewardRedemption,
            .chatNotification,
            .follow,
            .subscribe,
            .subscriptionEnd,
            .subscriptionGift,
            .subscriptionMessage,
            .raid,
            .goalProgress,
            .goalEnd,
            .vipAdd,
            .hypeTrainBegin,
            .hypeTrainProgress,
            .hypeTrainEnd
        ]
        for kind in kinds {
            #expect(NotificationTemplates.defaultTemplate(for: kind) != nil, "нет шаблона для \(kind)")
        }
    }

    @Test("Для остальных событий шаблон не задан")
    func defaultTemplateIsNilForOtherKinds() {
        let kinds: [SubscriptionKind] = [
            .chatMessage,
            .chatClear,
            .chatClearUserMessages,
            .chatMessageDelete,
            .streamUpdate,
            .ban,
            .unban,
            .vipRemove,
            .other("unknown.event")
        ]
        for kind in kinds {
            #expect(NotificationTemplates.defaultTemplate(for: kind) == nil, "лишний шаблон для \(kind)")
        }
    }

    @Test("Переопределение шаблона имеет приоритет над значением по умолчанию")
    func overridesTakePriority() {
        let override = NotificationTemplate(title: "Своё", body: "Здесь {user}")
        let template = NotificationTemplates.template(for: .follow, overrides: [.follow: override])
        #expect(template == override)
    }

    // MARK: - Подстановка

    @Test("Рейд: подставляются все поля")
    func raidRendersAllFields() {
        let rendered = NotificationTemplates.defaultTemplate(for: .raid)!.rendered(with: [
            "user": "Raider",
            "to": "Streamer",
            "viewers": "42"
        ])
        #expect(rendered.title == "Рейд!")
        #expect(rendered.body == "Raider привёл 42 зрителей")
    }

    @Test("Подписка: необязательный фрагмент сохраняется при наличии tier")
    func subscribeKeepsOptionalTierWhenPresent() {
        let rendered = NotificationTemplates.defaultTemplate(for: .subscribe)!.rendered(with: [
            "user": "Awesome_User",
            "tier": "1000"
        ])
        #expect(rendered.body == "Awesome_User · Tier 1000")
    }

    @Test("Подписка: необязательный фрагмент убирается без tier")
    func subscribeDropsOptionalTierWhenAbsent() {
        let rendered = NotificationTemplates.defaultTemplate(for: .subscribe)!.rendered(with: [
            "user": "Awesome_User"
        ])
        #expect(rendered.body == "Awesome_User")
    }

    @Test("Анонимный подарок использует текст по умолчанию")
    func anonymousGiftUsesFallback() {
        let rendered = NotificationTemplates.defaultTemplate(for: .subscriptionGift)!.rendered(with: [
            "total": "5",
            "tier": "1000"
        ])
        #expect(rendered.body == "Анонимный подарок · 5× Tier 1000")
    }

    @Test("Именованный подарок подставляет имя дарителя")
    func namedGiftUsesUserName() {
        let rendered = NotificationTemplates.defaultTemplate(for: .subscriptionGift)!.rendered(with: [
            "user": "Generous_Gifter",
            "total": "5",
            "tier": "1000"
        ])
        #expect(rendered.body == "Generous_Gifter · 5× Tier 1000")
    }

    @Test("Цель: подставляются заголовок и суммы")
    func goalProgressRendersAmounts() {
        let rendered = NotificationTemplates.defaultTemplate(for: .goalProgress)!.rendered(with: [
            "goal": "1000 отжиманий",
            "progress": "1",
            "goalAmount": "1000"
        ])
        #expect(rendered.body == "1000 отжиманий · 1/1000")
    }

    @Test("Цель: без сумм остаётся только заголовок")
    func goalProgressWithoutAmounts() {
        let rendered = NotificationTemplates.defaultTemplate(for: .goalProgress)!.rendered(with: [
            "goal": "1000 отжиманий"
        ])
        #expect(rendered.body == "1000 отжиманий")
    }

    @Test("Отсутствующий плейсхолдер превращается в пустую строку")
    func missingPlaceholderBecomesEmpty() {
        let template = NotificationTemplate(body: "A{missing}B")
        #expect(template.rendered(with: [:]).body == "AB")
    }

    @Test("Отсутствующий заголовок не подставляется")
    func nilTitleStaysNil() {
        let template = NotificationTemplate(body: "{user}")
        let rendered = template.rendered(with: ["user": "User"])
        #expect(rendered.title == nil)
        #expect(rendered.body == "User")
    }

    @Test("Повторяющиеся пробелы схлопываются, края обрезаются")
    func whitespaceIsNormalized() {
        let rendered = NotificationTemplate(body: "  {user}   [ · {reward}]  ").rendered(with: [
            "user": "User",
            "reward": "Обед"
        ])
        #expect(rendered.body == "User · Обед")
    }

    // MARK: - Разрешение содержимого события

    @Test("Событие из списка разрешается через шаблон")
    func renderedFollowUsesTemplate() {
        let event = EventSubNotice(
            kind: .follow,
            subscriptionType: "channel.follow",
            userName: "Awesome_User",
            fields: ["user": "Awesome_User"]
        )
        let rendered = NotificationTemplates.rendered(for: event)
        #expect(rendered.title == "Новый подписчик")
        #expect(rendered.body == "Awesome_User")
    }

    @Test("Рейд: тело собирается из полей шаблона")
    func renderedRaidIncludesViewers() {
        let event = EventSubNotice(
            kind: .raid,
            subscriptionType: "channel.raid",
            fields: ["user": "Raider", "to": "Streamer", "viewers": "42"]
        )
        let rendered = NotificationTemplates.rendered(for: event)
        #expect(rendered.title == "Рейд!")
        #expect(rendered.body == "Raider привёл 42 зрителей")
    }

    @Test("Событие без шаблона показывается без заголовка, тело — тип подписки")
    func renderedUntemplatedFallsBackToType() {
        let event = EventSubNotice(kind: .ban, subscriptionType: "channel.ban")
        let rendered = NotificationTemplates.rendered(for: event)
        #expect(rendered.title == nil)
        #expect(rendered.body == "channel.ban")
    }

    @Test("Событие без шаблона с заголовком использует его как тело")
    func renderedUntemplatedUsesEventTitle() {
        let event = EventSubNotice(
            kind: .streamUpdate,
            subscriptionType: "channel.update",
            title: "Новое название стрима"
        )
        let rendered = NotificationTemplates.rendered(for: event)
        #expect(rendered.title == nil)
        #expect(rendered.body == "Новое название стрима")
    }
}

@MainActor
@Suite("Уведомления: модель")
struct NotificationModelTests {

    @Test("Плоский текст склеивает заголовок и тело")
    func textCombinesTitleAndBody() {
        let notification = Notification(
            id: UUID(),
            kind: .follow,
            title: "Новый подписчик",
            body: "Awesome_User",
            sender: "Awesome_User",
            senderColor: .gray
        )
        #expect(notification.text == "Новый подписчик — Awesome_User")
    }

    @Test("Без заголовка плоский текст равен телу")
    func textWithoutTitleEqualsBody() {
        let notification = Notification(
            id: UUID(),
            kind: .ban,
            title: nil,
            body: "channel.ban",
            sender: "eventsub",
            senderColor: .gray
        )
        #expect(notification.text == "channel.ban")
    }
}
