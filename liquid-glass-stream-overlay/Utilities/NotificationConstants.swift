//
//  NotificationConstants.swift
//  Централизованные константы экрана уведомлений: размеры, отступы,
//  лимиты стека и длительность показа.
//

import SwiftUI

/// Строки и числа, общие для стека уведомлений и карточки уведомления.
///
/// Пользовательские тексты шаблонов (заголовки и тела событий) — это строки
/// в `NotificationTemplates.defaultTemplate(for:)`; при добавлении локализации
/// они переводятся через String Catalog, сюда выносить их не нужно.
enum NotificationConstants {
    // MARK: - Стек уведомлений
    /// Максимум одновременно отображаемых карточек.
    static let maxVisibleItems = 12
    /// Расстояние между карточками по вертикали.
    static let stackSpacing: CGFloat = 16
    /// Высота карточки до первого измерения раскладки.
    static let defaultRowHeight: CGFloat = 48

    // MARK: - Карточка уведомления
    /// Горизонтальные отступы внутри карточки.
    static let cardPaddingH: CGFloat = 24
    /// Вертикальные отступы внутри карточки.
    static let cardPaddingV: CGFloat = 20
    /// Радиус скругления углов карточки.
    static let cardCornerRadius: CGFloat = 32
    /// Размер иконки события.
    static let iconSize: CGFloat = 60
    /// Зазор между иконкой и текстом.
    static let iconSpacing: CGFloat = 16
    /// Размер шрифта заголовка.
    static let titleFontSize: CGFloat = 16
    /// Размер шрифта тела уведомления.
    static let bodyFontSize: CGFloat = 26

    // MARK: - Показ уведомлений
    /// Время (сек) до автоочистки уведомления.
    static let displayTime: TimeInterval = 5
    /// Имя ассета иконки по умолчанию.
    static let defaultIcon = "Twitch"
    /// Подпись отправителя события-уведомления в общем стеке сообщений.
    static let notificationSender = "Twitch"
    /// Цвет подписи отправителя события-уведомления в общем стеке сообщений.
    static let notificationSenderColor: Color = Color(red: 145 / 255, green: 70 / 255, blue: 255 / 255)
}
