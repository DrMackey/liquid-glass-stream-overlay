// NotificationTemplate.swift
// Шаблоны текста уведомлений и подстановка значений события
//
// Синтаксис шаблона:
//   {key}            — значение поля события; если поля нет — подставляется пусто;
//   {key|fallback}   — значение поля, а при его отсутствии — текст `fallback`;
//   [ ... ]          — необязательный фрагмент: попадает в результат только если
//                      внутри есть плейсхолдер с непустым значением (либо
//                      плейсхолдеров нет вовсе).

import Foundation
import SwiftUI

/// Оформление и текстовый шаблон уведомления для одного типа события.
///
/// Экземпляр хранит строки с плейсхолдерами; готовый к показу текст получается
/// через `rendered(with:)`, который подставляет значения из `EventSubNotice.fields`.
nonisolated struct NotificationTemplate: Equatable {

    /// Строка заголовка. `nil` означает, что заголовок показывать не нужно.
    let title: String?
    /// Строка текста (тело) уведомления.
    let body: String
    /// Имя ассета иконки. `nil` — иконка по умолчанию (Twitch).
    let icon: String?
    /// Акцентный цвет карточки. `nil` — без акцента.
    let accent: Color?

    init(title: String? = nil, body: String, icon: String? = nil, accent: Color? = nil) {
        self.title = title
        self.body = body
        self.icon = icon
        self.accent = accent
    }

    /// Подставляет значения полей события и возвращает готовое содержимое.
    func rendered(with fields: [String: String]) -> RenderedNotification {
        let renderedTitle = title.flatMap { raw -> String? in
            let value = Self.substitute(raw, fields: fields)
            return value.isEmpty ? nil : value
        }
        return RenderedNotification(
            title: renderedTitle,
            body: Self.substitute(body, fields: fields),
            icon: icon,
            accent: accent
        )
    }

    // MARK: - Подстановка

    /// Раскрывает плейсхолдеры и необязательные фрагменты шаблона.
    static func substitute(_ template: String, fields: [String: String]) -> String {
        normalize(resolve(template, fields: fields).text)
    }

    /// Разбор без нормализации пробелов.
    ///
    /// Возвращает текст и признаки: встретился ли хоть один плейсхолдер и
    /// подставился ли хоть один непустой. По ним решается судьба необязательных
    /// фрагментов `[ ... ]`: они попадают в результат, только если внутри есть
    /// непустое значение либо нет плейсхолдеров вовсе.
    private static func resolve(
        _ template: String,
        fields: [String: String]
    ) -> (text: String, hasPlaceholder: Bool, hasValue: Bool) {
        var text = ""
        var hasPlaceholder = false
        var hasValue = false
        var index = template.startIndex

        while index < template.endIndex {
            let character = template[index]

            if character == "{" {
                if let close = template[index...].firstIndex(of: "}") {
                    let token = String(template[template.index(after: index)..<close])
                    let value = resolveToken(token, fields: fields)
                    hasPlaceholder = true
                    if !value.isEmpty { hasValue = true }
                    text += value
                    index = template.index(after: close)
                    continue
                }
            } else if character == "[" {
                if let close = matchingBracket(in: template, from: index) {
                    let inner = String(template[template.index(after: index)..<close])
                    let result = resolve(inner, fields: fields)
                    if !result.hasPlaceholder || result.hasValue {
                        text += result.text
                        hasPlaceholder = hasPlaceholder || result.hasPlaceholder
                        hasValue = hasValue || result.hasValue
                    }
                    index = template.index(after: close)
                    continue
                }
            }

            text.append(character)
            index = template.index(after: index)
        }

        return (text, hasPlaceholder, hasValue)
    }

    /// Разбирает один токен `key` или `key|fallback`.
    private static func resolveToken(_ token: String, fields: [String: String]) -> String {
        let parts = token.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        if let value = fields[key], !value.isEmpty {
            return value
        }
        if parts.count == 2 {
            return String(parts[1])
        }
        return ""
    }

    /// Находит парную закрывающую скобку `]` с учётом вложенности.
    private static func matchingBracket(in string: String, from open: String.Index) -> String.Index? {
        var depth = 0
        var index = open
        while index < string.endIndex {
            let character = string[index]
            if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = string.index(after: index)
        }
        return nil
    }

    /// Схлопывает повторяющиеся пробелы и убирает пробелы по краям.
    private static func normalize(_ string: String) -> String {
        var output = ""
        var previousWasSpace = false
        for character in string {
            if character == " " {
                if previousWasSpace { continue }
                previousWasSpace = true
            } else {
                previousWasSpace = false
            }
            output.append(character)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Готовое к показу содержимое уведомления: шаблон после подстановки значений.
nonisolated struct RenderedNotification: Equatable {
    let title: String?
    let body: String
    let icon: String?
    let accent: Color?
}

/// Набор шаблонов по типам событий.
nonisolated enum NotificationTemplates {

    /// Шаблон по умолчанию для типа события.
    ///
    /// `nil` означает, что для этого события уведомление не формируется.
    static func defaultTemplate(for kind: SubscriptionKind) -> NotificationTemplate? {
        switch kind {
        case .channelPointsRewardRedemption:
            return NotificationTemplate(title: "Новая награда", body: "{user} — {reward}")
        case .chatNotification:
            return NotificationTemplate(title: "Уведомление", body: "{text}")
        case .follow:
            return NotificationTemplate(title: "Новый подписчик", body: "{user}")
        case .subscribe:
            return NotificationTemplate(title: "Новая подписка", body: "{user}[ · Tier {tier}]")
        case .subscriptionEnd:
            return NotificationTemplate(title: "Подписка завершилась", body: "{user}[ · Tier {tier}]")
        case .subscriptionGift:
            return NotificationTemplate(title: "Подарочная подписка", body: "{user|Анонимный подарок}[ · {total}× Tier {tier}]")
        case .subscriptionMessage:
            return NotificationTemplate(title: "Продление подписки", body: "{user}[ · {months} мес.]")
        case .raid:
            return NotificationTemplate(title: "Рейд!", body: "{user} привёл {viewers} зрителей")
        case .goalProgress:
            return NotificationTemplate(title: "Прогресс цели", body: "{goal}[ · {progress}/{goalAmount}]")
        case .goalEnd:
            return NotificationTemplate(title: "Цель достигнута", body: "{goal}")
        case .vipAdd:
            return NotificationTemplate(title: "Новый VIP", body: "{user}")
        case .hypeTrainBegin:
            return NotificationTemplate(title: "Хайптрейн начался", body: "Собрано {total}")
        case .hypeTrainProgress:
            return NotificationTemplate(title: "Хайптрейн", body: "Собрано {total}[ · цель {goalAmount}]")
        case .hypeTrainEnd:
            return NotificationTemplate(title: "Хайптрейн завершён", body: "Итог {total}")
        default:
            return nil
        }
    }

    /// Возвращает шаблон с учётом возможных переопределений.
    ///
    /// `overrides` — задел на будущее: пользовательские шаблоны, заданные извне,
    /// имеют приоритет над значениями по умолчанию.
    static func template(
        for kind: SubscriptionKind,
        overrides: [SubscriptionKind: NotificationTemplate] = [:]
    ) -> NotificationTemplate? {
        overrides[kind] ?? defaultTemplate(for: kind)
    }

    /// Готовое содержимое уведомления для события.
    ///
    /// Для событий из списка шаблонов используется шаблон; остальные события
    /// показываются без заголовка — телом служит заголовок события или его тип.
    static func rendered(for event: EventSubNotice) -> RenderedNotification {
        if let rendered = defaultTemplate(for: event.kind)?.rendered(with: event.fields) {
            let body = rendered.body.isEmpty ? (event.title ?? event.subscriptionType) : rendered.body
            return RenderedNotification(title: rendered.title, body: body,
                                        icon: rendered.icon, accent: rendered.accent)
        }
        return RenderedNotification(title: nil,
                                    body: event.title ?? event.subscriptionType,
                                    icon: nil, accent: nil)
    }
}
