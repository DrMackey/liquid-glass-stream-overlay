// EventSubRouter.swift
// Маршрутизация типизированных событий EventSub в действия приложения

import Foundation

/// Переводит событие EventSub в список намерений приложения.
///
/// Роутер не знает ни о сокете, ни о подписках, ни об UI: он только отражает
/// семантику протокола. Форматирование текста, работа с бейджами и обновление
/// моделей интерфейса остаются в `TwitchChatManager`.
///
/// Возврат массива, а не одного значения, позволяет не заводить `.noop`:
/// события без реакции (`session_keepalive`, неизвестные типы) дают пустой массив.
nonisolated enum EventSubRouter {

    /// Что менеджеру нужно сделать в ответ на событие.
    nonisolated enum Action: Sendable, Equatable {

        /// Сессия установлена — нужно подписаться на типы событий.
        case subscribe(sessionId: String)
        /// Twitch попросил переподключиться. `url` — `session.reconnect_url`,
        /// если Twitch его прислал и адрес разбирается; иначе `nil`, и клиент
        /// переподключается к прежнему адресу сам.
        case reconnect(url: URL?)
        /// Новое сообщение чата.
        case chat(ChatMessageEvent)
        /// Событие прочей подписки — показать уведомление.
        case notice(EventSubNotice)
        /// Подписка была отозвана.
        case revoke(subscriptionType: String)
    }

    /// Возвращает действия для события; пустой массив означает «реакция не нужна».
    static func actions(for event: EventSubEvent) -> [Action] {
        switch event {
        case .sessionWelcome(let id):
            return [.subscribe(sessionId: id)]

        case .sessionReconnect(let reconnectURL):
            return [.reconnect(url: Self.endpoint(from: reconnectURL))]

        case .notification(let payload):
            switch payload {
            case .chat(let chat):
                return [.chat(chat)]
            case .event(let notice):
                return [.notice(notice)]
            case .unsupported:
                // Тип подписки приложению неизвестен: показывать нечего.
                return []
            }

        case .revocation(let subscriptionType):
            return [.revoke(subscriptionType: subscriptionType)]

        case .sessionKeepalive, .unknown:
            return []
        }
    }

    /// Оставляет только тот `reconnect_url`, в который можно пойти.
    ///
    /// `URL(string:)` слишком снисходителен: он превращает в URL почти любую
    /// строку, включая мусор без схемы. Такой адрес не сломал бы разбор, но вёл
    /// бы к бесконечным неудачным попыткам подключения, поэтому схема и хост
    /// проверяются явно. Всё остальное — повод вернуться к исходному адресу.
    private static func endpoint(from raw: String?) -> URL? {
        guard let raw,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              url.host?.isEmpty == false
        else { return nil }

        // Поддерживаем только те схемы, которые вообще говорит Twitch.
        guard scheme == "wss" || scheme == "ws" else { return nil }
        return url
    }
}