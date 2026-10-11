//
//  NotificationCardView.swift
//  Карточка уведомления: иконка, заголовок и текст, как в мобильном уведомлении.
//

import SwiftUI

/// Карточка события Twitch: иконка слева, заголовок и текст справа.
///
/// Заголовок необязателен — при `nil` (или пустой строке) показывается только текст.
/// Иконка и акцент берутся из `Notification`, с общими значениями по умолчанию.
struct NotificationCardView: View {
    let notification: Notification
    var maxWidth: CGFloat = .infinity
    var contentPaddingH: CGFloat = NotificationConstants.cardPaddingH
    var contentPaddingV: CGFloat = NotificationConstants.cardPaddingV
    var bubbleCornerRadius: CGFloat = NotificationConstants.cardCornerRadius
    var iconSize: CGFloat = NotificationConstants.iconSize
    var titleFontSize: CGFloat = NotificationConstants.titleFontSize
    var bodyFontSize: CGFloat = NotificationConstants.bodyFontSize

    /// Имя ассета иконки; при отсутствии — общая иконка Twitch.
    private var iconName: String { notification.icon ?? NotificationConstants.defaultIcon }

    /// Цвет заголовка: акцент события, иначе системный основной цвет.
    private var titleColor: Color { notification.accent ?? .primary }

    var body: some View {
        HStack(alignment: .top, spacing: NotificationConstants.iconSpacing) {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if let title = notification.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: titleFontSize, weight: .semibold))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                }
                Text(notification.body)
                    .font(.system(size: bodyFontSize))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, contentPaddingH)
        .padding(.vertical, contentPaddingV)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: bubbleCornerRadius))
    }
}

private func previewNotification(
    _ kind: SubscriptionKind,
    title: String?,
    body: String,
    accent: Color? = nil
) -> Notification {
    Notification(
        id: UUID(),
        kind: kind,
        title: title,
        body: body,
        accent: accent,
        sender: "eventsub",
        senderColor: .gray
    )
}

#Preview("Уведомления") {
    VStack(spacing: 16) {
        NotificationCardView(notification: previewNotification(
            .follow, title: "Новый подписчик", body: "Awesome_User"
        ))
        NotificationCardView(notification: previewNotification(
            .raid, title: "Рейд!", body: "Raider привёл 42 зрителей", accent: .purple
        ))
        NotificationCardView(notification: previewNotification(
            .subscriptionGift, title: "Подарочная подписка", body: "Анонимный подарок · 5× Tier 1"
        ))
        NotificationCardView(notification: previewNotification(
            .channelPointsRewardRedemption, title: "Новая награда", body: "Cool_Viewer — Обед в студии"
        ))
        NotificationCardView(notification: previewNotification(
            .other("unknown.event"), title: nil, body: "Текст без заголовка — длинный пример, который переносится на несколько строк."
        ))
    }
    .padding(40)
    .frame(maxWidth: 520)
    .background(Color.black.opacity(0.85))
}
