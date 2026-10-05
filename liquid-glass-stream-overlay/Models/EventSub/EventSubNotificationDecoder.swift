// EventSubNotificationDecoder.swift
// Разбор payload'а notification по типу подписки

import Foundation

/// Декодирует `payload.event` в модель, соответствующую типу подписки.
///
/// `switch` по `SubscriptionKind` исчерпывающий: появление нового типа в Twitch
/// заставит компилятор потребовать решение здесь, а не приводить к молчаливой
/// потере события в UI.
nonisolated enum EventSubNotificationDecoder {

    static func decode(
        kind: SubscriptionKind,
        messageId: String?,
        from container: KeyedDecodingContainer<EventSubEvent.CodingKeys>
    ) throws -> EventSubNotificationPayload {
        let payload = try container.nestedContainer(keyedBy: EventSubEvent.PayloadKeys.self, forKey: .payload)

        func notice<T: Decodable>(_ type: T.Type, _ project: (T) -> EventSubNotice) throws -> EventSubNotificationPayload {
            let event = try payload.decode(type, forKey: .event)
            return .event(project(event).withMessageId(messageId))
        }

        switch kind {
        case .chatMessage:
            // Сообщения чата — горячий путь, у них своя модель и свой маршрут.
            return .chat(try payload.decode(ChatMessageEvent.self, forKey: .event))

        case .channelPointsRewardRedemption:
            return try notice(RewardRedemptionEvent.self) { $0.notice }

        case .chatClear:
            return try notice(ChatClearEvent.self) { $0.notice }

        case .chatClearUserMessages:
            return try notice(ChatClearUserMessagesEvent.self) { $0.notice }

        case .chatMessageDelete:
            return try notice(ChatMessageDeleteEvent.self) { $0.notice }

        case .chatNotification:
            return try notice(ChatNotificationEvent.self) { $0.notice }

        case .follow:
            return try notice(FollowEvent.self) { $0.notice }

        case .subscribe:
            return try notice(SubscribeEvent.self) { $0.notice }

        case .subscriptionEnd:
            return try notice(SubscriptionEndEvent.self) { $0.notice }

        case .subscriptionGift:
            return try notice(SubscriptionGiftEvent.self) { $0.notice }

        case .subscriptionMessage:
            return try notice(SubscriptionMessageEvent.self) { $0.notice }

        case .raid:
            return try notice(RaidEvent.self) { $0.notice }

        case .goalProgress:
            return try notice(GoalProgressEvent.self) { $0.notice }

        case .goalEnd:
            return try notice(GoalEndEvent.self) { $0.notice }

        case .streamUpdate:
            return try notice(StreamUpdateEvent.self) { $0.notice }

        case .ban:
            return try notice(BanEvent.self) { $0.notice }

        case .unban:
            return try notice(UnbanEvent.self) { $0.notice }

        case .vipAdd:
            return try notice(VipEvent.self) { $0.notice(for: .vipAdd) }

        case .vipRemove:
            return try notice(VipEvent.self) { $0.notice(for: .vipRemove) }

        case .hypeTrainBegin:
            return try notice(HypeTrainEvent.self) { $0.notice(for: .hypeTrainBegin) }

        case .hypeTrainProgress:
            return try notice(HypeTrainEvent.self) { $0.notice(for: .hypeTrainProgress) }

        case .hypeTrainEnd:
            return try notice(HypeTrainEvent.self) { $0.notice(for: .hypeTrainEnd) }

        case .other:
            // Тип подписки неизвестен приложению: событие принимается и логируется,
            // но не превращается в уведомление. Разбор `payload.event` пропускаем.
            return .unsupported(subscriptionType: kind.rawValue)
        }
    }
}