// EventSubEvent.swift
// Типизированная модель входящего сообщения EventSub

import Foundation

/// Разобранное сообщение EventSub WebSocket.
///
/// Декодируется одним проходом `JSONDecoder`: тип сообщения определяется по
/// `metadata.message_type`, а payload — по `metadata.subscription_type`.
/// Промежуточного `Any`/`[String: Any]` и рекурсивного поиска по дереву нет.
///
/// Спецификация: https://dev.twitch.tv/docs/eventsub/websocket-reference/
///
/// Модель объявлена `nonisolated`: она состоит только из значений и свободна
/// от доступа к UI, поэтому её можно передавать через `AsyncStream` из
/// сетевого потока в главный актор без нарушения изоляции.
nonisolated enum EventSubEvent: Decodable, Sendable {

    /// `session_welcome` — сессия установлена, `id` нужен для подписки.
    case sessionWelcome(id: String)
    /// `session_keepalive` — сессия жива, ничего делать не нужно.
    case sessionKeepalive
    /// `session_reconnect` — Twitch просит переподключиться.
    case sessionReconnect(reconnectURL: String?)
    /// `notification` — событие одной из подписок.
    case notification(payload: EventSubNotificationPayload)
    /// `revocation` — подписка была отозвана.
    case revocation(subscriptionType: String)
    /// Неизвестный `message_type` — игнорируется.
    case unknown(messageType: String)

    // MARK: - Метаданные

    private struct Metadata: Decodable {
        let message_id: String?
        let message_type: String
        let subscription_type: String?
    }

    // MARK: - Payload сессии

    private struct SessionPayload: Decodable {
        struct Session: Decodable {
            let id: String?
            let reconnect_url: String?
        }
        let session: Session?
    }

    enum CodingKeys: String, CodingKey {
        case metadata
        case payload
    }

    enum PayloadKeys: String, CodingKey {
        case event
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let metadata = try container.decode(Metadata.self, forKey: .metadata)

        switch metadata.message_type {
        case "session_welcome":
            let payload = try container.decode(SessionPayload.self, forKey: .payload)
            guard let id = payload.session?.id else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: container.codingPath + [CodingKeys.payload],
                          debugDescription: "session_welcome без session.id")
                )
            }
            self = .sessionWelcome(id: id)

        case "session_keepalive":
            self = .sessionKeepalive

        case "session_reconnect":
            let payload = try container.decode(SessionPayload.self, forKey: .payload)
            self = .sessionReconnect(reconnectURL: payload.session?.reconnect_url)

        case "notification":
            let kind = SubscriptionKind.parse(metadata.subscription_type ?? "")
            self = .notification(payload: try EventSubNotificationDecoder.decode(
                kind: kind,
                messageId: metadata.message_id,
                from: container
            ))

        case "revocation":
            self = .revocation(subscriptionType: metadata.subscription_type ?? "")

        default:
            self = .unknown(messageType: metadata.message_type)
        }
    }
}

// MARK: - Payload нотификации

/// Payload события подписки.
nonisolated enum EventSubNotificationPayload: Sendable, Equatable {
    /// `channel.chat.message` — горячий путь, отдельная модель и отдельный маршрут.
    case chat(ChatMessageEvent)
    /// Любая другая подписка, разобранная в её собственную модель.
    case event(EventSubNotice)
    /// Тип подписки неизвестен приложению: событие игнорируется, но не считается ошибкой.
    case unsupported(subscriptionType: String)
}

// MARK: - События

/// Сообщение чата — горячий путь, декодируется полностью типизированно.
nonisolated struct ChatMessageEvent: Decodable, Sendable, Equatable {

    /// Бейдж чата. Набор и порядок приходят от Twitch.
    struct Badge: Decodable, Equatable, Sendable {
        let set_id: String
        let id: String

        var pair: (String, String) { (set_id, id) }
    }

    private struct Message: Decodable {
        let text: String
    }

    let chatterUserName: String
    let text: String
    let badges: [Badge]
    let rawColorHex: String?

    /// Пустой цвет от Twitch означает «цвет по умолчанию» и трактуется как nil.
    var colorHex: String? {
        guard let rawColorHex, !rawColorHex.isEmpty else { return nil }
        return rawColorHex
    }

    /// Бейджи в виде пар `(set_id, id)` для `Message`.
    var badgePairs: [(String, String)] {
        badges.map(\.pair)
    }

    enum CodingKeys: String, CodingKey {
        case chatter_user_name
        case message
        case badges
        case color
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chatterUserName = try container.decode(String.self, forKey: .chatter_user_name)
        text = try container.decode(Message.self, forKey: .message).text
        badges = (try? container.decode([Badge].self, forKey: .badges)) ?? []
        rawColorHex = try? container.decodeIfPresent(String.self, forKey: .color)
    }
}
