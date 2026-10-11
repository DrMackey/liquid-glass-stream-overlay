//
//  NotifiactionModel.swift
//  liquid-glass-stream-overlay
//
//  Created by Rodney Mackey on 01.11.2025.
//

import Foundation
import SwiftUI

/// Уведомление о событии Twitch: заголовок и текст, как в мобильном уведомлении.
struct Notification: Equatable, Identifiable {
    let id: UUID
    /// Тип события, породившего уведомление.
    let kind: SubscriptionKind
    /// Заголовок уведомления. `nil` — показывать без заголовка.
    let title: String?
    /// Текст (тело) уведомления.
    let body: String
    /// Имя ассета иконки. `nil` — иконка по умолчанию.
    let icon: String?
    /// Акцентный цвет карточки. `nil` — без акцента.
    let accent: Color?
    let sender: String
    let senderColor: Color?
    let badges: [(String, String)]
    let badgeViewData: [BadgeViewData]

    /// Плоский текст «заголовок — тело» для общего потока сообщений.
    var text: String {
        guard let title, !title.isEmpty else { return body }
        return "\(title) — \(body)"
    }

    init(
        id: UUID,
        kind: SubscriptionKind,
        title: String?,
        body: String,
        icon: String? = nil,
        accent: Color? = nil,
        sender: String,
        senderColor: Color?,
        badges: [(String, String)] = [],
        badgeViewData: [BadgeViewData] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.icon = icon
        self.accent = accent
        self.sender = sender
        self.senderColor = senderColor
        self.badges = badges
        self.badgeViewData = badgeViewData
    }

    static func == (lhs: Notification, rhs: Notification) -> Bool {
        lhs.id == rhs.id &&
        lhs.kind == rhs.kind &&
        lhs.title == rhs.title &&
        lhs.body == rhs.body &&
        lhs.icon == rhs.icon &&
        lhs.accent == rhs.accent &&
        lhs.sender == rhs.sender &&
        lhs.badges.elementsEqual(rhs.badges, by: { $0.0 == $1.0 && $0.1 == $1.1 }) &&
        lhs.senderColor == rhs.senderColor &&
        lhs.badgeViewData == rhs.badgeViewData
    }
}
