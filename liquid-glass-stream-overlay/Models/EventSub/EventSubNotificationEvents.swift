// EventSubNotificationEvents.swift
// Типизированные модели событий подписок EventSub
//
// https://dev.twitch.tv/docs/eventsub/eventsub-subscription-types/

import Foundation

/// Тип подписки, на который пришло событие.
///
/// Значение совпадает со строкой `metadata.subscription_type`, поэтому его
/// можно использовать и для подписки, и для логов.
nonisolated enum SubscriptionKind: Hashable, Sendable {
    case channelPointsRewardRedemption
    case chatMessage
    case chatClear
    case chatClearUserMessages
    case chatMessageDelete
    case chatNotification
    case follow
    case subscribe
    case subscriptionEnd
    case subscriptionGift
    case subscriptionMessage
    case raid
    case goalProgress
    case goalEnd
    case streamUpdate
    case ban
    case unban
    case vipAdd
    case vipRemove
    case hypeTrainBegin
    case hypeTrainProgress
    case hypeTrainEnd
    /// Тип, которого нет в приложении: декодируется, но не интерпретируется.
    case other(String)

    /// Разбирает `subscription_type` Twitch в конкретный случай.
    ///
    /// Список строк и `rawValue` намеренно хранятся раздельно: первое место
    /// читается человеком, второе используется для подписки. Расхождение между
    /// ними ловит тест `subscriptionKindMatchesTwitchStrings`.
    nonisolated static func parse(_ rawValue: String) -> SubscriptionKind {
        switch rawValue {
        case "channel.channel_points_custom_reward_redemption.add": return .channelPointsRewardRedemption
        case "channel.chat.message": return .chatMessage
        case "channel.chat.clear": return .chatClear
        case "channel.chat.clear_user_messages": return .chatClearUserMessages
        case "channel.chat.message_delete": return .chatMessageDelete
        case "channel.chat.notification": return .chatNotification
        case "channel.follow": return .follow
        case "channel.subscribe": return .subscribe
        case "channel.subscription.end": return .subscriptionEnd
        case "channel.subscription.gift": return .subscriptionGift
        case "channel.subscription.message": return .subscriptionMessage
        case "channel.raid": return .raid
        case "channel.goal.progress": return .goalProgress
        case "channel.goal.end": return .goalEnd
        case "channel.update": return .streamUpdate
        case "channel.ban": return .ban
        case "channel.unban": return .unban
        case "channel.vip.add": return .vipAdd
        case "channel.vip.remove": return .vipRemove
        case "channel.hype_train.begin": return .hypeTrainBegin
        case "channel.hype_train.progress": return .hypeTrainProgress
        case "channel.hype_train.end": return .hypeTrainEnd
        default: return .other(rawValue)
        }
    }
}

/// Единообразная проекция события подписки для интерфейса.
///
/// Декодирование остаётся строго типизированным (в `EventSubNotificationDecoder`),
/// но наверх поднимается только то, что нужно оверлею: кто автор, что показать
/// и какого типа было событие. Поле `title` заполняется лишь там, где у Twitch
/// есть прямой аналог заголовка; остальные события оставляют его пустым, и
/// вызывающий код решает, что показать вместо него.
nonisolated struct EventSubNotice: Sendable, Equatable {

    /// Тип подписки, определяет дальнейшую интерпретацию.
    let kind: SubscriptionKind
    /// Строка `metadata.subscription_type`.
    let subscriptionType: String
    /// `metadata.message_id` — идентификатор сообщения EventSub.
    let messageId: String?
    /// Пользователь, какому посвящено событие.
    let userName: String?
    /// Заголовок: награда, текст уведомления в чате, название цели, заголовок стрима.
    let title: String?

    init(
        kind: SubscriptionKind,
        subscriptionType: String,
        messageId: String? = nil,
        userName: String? = nil,
        title: String? = nil
    ) {
        self.kind = kind
        self.subscriptionType = subscriptionType
        self.messageId = messageId
        self.userName = userName
        self.title = title
    }

    /// Дополняет проекцию идентификатором сообщения из `metadata`.
    func withMessageId(_ messageId: String?) -> EventSubNotice {
        EventSubNotice(
            kind: kind,
            subscriptionType: subscriptionType,
            messageId: messageId,
            userName: userName,
            title: title
        )
    }
}

// MARK: - Баллы канала

/// `channel.channel_points_custom_reward_redemption.add`
nonisolated struct RewardRedemptionEvent: Decodable, Equatable {
    let user_name: String
    let reward: Reward
    let user_input: String?

    struct Reward: Decodable, Equatable {
        let title: String
    }

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .channelPointsRewardRedemption,
            subscriptionType: SubscriptionKind.channelPointsRewardRedemption.rawValue,
            userName: user_name,
            title: reward.title
        )
    }
}

// MARK: - События чата кроме сообщений

/// `channel.chat.clear` — у чата нет субъекта, кроме канала.
nonisolated struct ChatClearEvent: Decodable, Equatable {
    var notice: EventSubNotice {
        EventSubNotice(kind: .chatClear, subscriptionType: SubscriptionKind.chatClear.rawValue)
    }
}

/// `channel.chat.clear_user_messages` — удалены все сообщения пользователя.
nonisolated struct ChatClearUserMessagesEvent: Decodable, Equatable {
    let target_user_name: String

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .chatClearUserMessages,
            subscriptionType: SubscriptionKind.chatClearUserMessages.rawValue,
            userName: target_user_name
        )
    }
}

/// `channel.chat.message_delete` — удалено конкретное сообщение.
nonisolated struct ChatMessageDeleteEvent: Decodable, Equatable {
    let target_user_name: String

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .chatMessageDelete,
            subscriptionType: SubscriptionKind.chatMessageDelete.rawValue,
            userName: target_user_name
        )
    }
}

/// `channel.chat.notification` — системное уведомление в чате.
nonisolated struct ChatNotificationEvent: Decodable, Equatable {
    let chatter_user_name: String
    let message: Message

    struct Message: Decodable, Equatable {
        let text: String
    }

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .chatNotification,
            subscriptionType: SubscriptionKind.chatNotification.rawValue,
            userName: chatter_user_name,
            title: message.text
        )
    }
}

// MARK: - Подписки на канал

/// `channel.follow`
nonisolated struct FollowEvent: Decodable, Equatable {
    let user_name: String

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .follow,
            subscriptionType: SubscriptionKind.follow.rawValue,
            userName: user_name
        )
    }
}

/// `channel.subscribe`
nonisolated struct SubscribeEvent: Decodable, Equatable {
    let user_name: String
    let tier: String

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .subscribe,
            subscriptionType: SubscriptionKind.subscribe.rawValue,
            userName: user_name
        )
    }
}

/// `channel.subscription.end`
nonisolated struct SubscriptionEndEvent: Decodable, Equatable {
    let user_name: String
    let tier: String

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .subscriptionEnd,
            subscriptionType: SubscriptionKind.subscriptionEnd.rawValue,
            userName: user_name
        )
    }
}

/// `channel.subscription.gift` — имя может отсутствовать при анонимном подарке.
nonisolated struct SubscriptionGiftEvent: Decodable, Equatable {
    let user_name: String?
    let total: Int
    let tier: String

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .subscriptionGift,
            subscriptionType: SubscriptionKind.subscriptionGift.rawValue,
            userName: user_name
        )
    }
}

/// `channel.subscription.message` — сообщение к повторной подписке.
nonisolated struct SubscriptionMessageEvent: Decodable, Equatable {
    let user_name: String
    let message_text: String?
    let cumulative_months: Int

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .subscriptionMessage,
            subscriptionType: SubscriptionKind.subscriptionMessage.rawValue,
            userName: user_name,
            title: message_text
        )
    }
}

// MARK: - Рейды

/// `channel.raid` — набежавший канал и число зрителей.
///
/// `viewers` декодируется, но в заголовок не попадает: у Twitch нет поля
/// заголовка, а собирать текст вида «N зрителей» здесь означало бы вводить
/// непереводимую строку в слой декодирования.
nonisolated struct RaidEvent: Decodable, Equatable {
    let from_broadcaster_user_name: String
    let to_broadcaster_user_name: String
    let viewers: Int

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .raid,
            subscriptionType: SubscriptionKind.raid.rawValue,
            userName: from_broadcaster_user_name
        )
    }
}

// MARK: - Цели канала

/// Общая часть событий целей: у Twitch она одинакова для `progress` и `end`.
nonisolated struct Goal: Decodable, Equatable {
    let title: String
    let is_achieved: Bool?
    let current_amount: Int?
    let target_amount: Int?
}

/// `channel.goal.progress`
nonisolated struct GoalProgressEvent: Decodable, Equatable {
    let goal: Goal
    let progress: Double

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .goalProgress,
            subscriptionType: SubscriptionKind.goalProgress.rawValue,
            title: goal.title
        )
    }
}

/// `channel.goal.end`
nonisolated struct GoalEndEvent: Decodable, Equatable {
    let goal: Goal
    let ended_at: String

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .goalEnd,
            subscriptionType: SubscriptionKind.goalEnd.rawValue,
            title: goal.title
        )
    }
}

// MARK: - Стрим

/// `channel.update`
nonisolated struct StreamUpdateEvent: Decodable, Equatable {
    let title: String
    let category_name: String?

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .streamUpdate,
            subscriptionType: SubscriptionKind.streamUpdate.rawValue,
            title: title
        )
    }
}

// MARK: - Модерация

/// `channel.ban`
nonisolated struct BanEvent: Decodable, Equatable {
    let user_name: String
    let moderator_user_name: String?
    let reason: String?

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .ban,
            subscriptionType: SubscriptionKind.ban.rawValue,
            userName: user_name
        )
    }
}

/// `channel.unban`
nonisolated struct UnbanEvent: Decodable, Equatable {
    let user_name: String
    let moderator_user_name: String?

    var notice: EventSubNotice {
        EventSubNotice(
            kind: .unban,
            subscriptionType: SubscriptionKind.unban.rawValue,
            userName: user_name
        )
    }
}

/// Общая часть `channel.vip.add` и `channel.vip.remove`.
nonisolated struct VipEvent: Decodable, Equatable {
    let user_name: String

    func notice(for kind: SubscriptionKind) -> EventSubNotice {
        EventSubNotice(
            kind: kind,
            subscriptionType: kind.rawValue,
            userName: user_name
        )
    }
}

// MARK: - Хайптрейн

/// Общая часть событий хайптрейна.
///
/// Набор полей одинаков для `begin`, `progress` и `end`, но у Twitch `begin`
/// приходит с `progress` и `goal`, а `end` — без них, поэтому часть полей
/// опциональна. Проекция пустая: у хайптрейна нет ни пользователя, ни заголовка.
nonisolated struct HypeTrainEvent: Decodable, Equatable {
    let total: Int
    let progress: Int?
    let goal: Int?

    func notice(for kind: SubscriptionKind) -> EventSubNotice {
        EventSubNotice(kind: kind, subscriptionType: kind.rawValue)
    }
}

// MARK: - Сырые значения SubscriptionKind

extension SubscriptionKind {
    /// Значение, совпадающее со строкой Twitch.
    ///
    /// Для `.other` возвращается исходная строка, поэтому результат всегда
    /// пригоден для подписки на сервере.
    ///
    /// Члены `extension` не наследуют `nonisolated` от типа, поэтому
    /// изоляцию здесь нужно указать явно.
    nonisolated var rawValue: String {
        switch self {
        case .channelPointsRewardRedemption: return "channel.channel_points_custom_reward_redemption.add"
        case .chatMessage: return "channel.chat.message"
        case .chatClear: return "channel.chat.clear"
        case .chatClearUserMessages: return "channel.chat.clear_user_messages"
        case .chatMessageDelete: return "channel.chat.message_delete"
        case .chatNotification: return "channel.chat.notification"
        case .follow: return "channel.follow"
        case .subscribe: return "channel.subscribe"
        case .subscriptionEnd: return "channel.subscription.end"
        case .subscriptionGift: return "channel.subscription.gift"
        case .subscriptionMessage: return "channel.subscription.message"
        case .raid: return "channel.raid"
        case .goalProgress: return "channel.goal.progress"
        case .goalEnd: return "channel.goal.end"
        case .streamUpdate: return "channel.update"
        case .ban: return "channel.ban"
        case .unban: return "channel.unban"
        case .vipAdd: return "channel.vip.add"
        case .vipRemove: return "channel.vip.remove"
        case .hypeTrainBegin: return "channel.hype_train.begin"
        case .hypeTrainProgress: return "channel.hype_train.progress"
        case .hypeTrainEnd: return "channel.hype_train.end"
        case .other(let raw): return raw
        }
    }
}