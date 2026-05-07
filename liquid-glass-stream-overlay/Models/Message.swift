//
//  EmoteModel.swift
//  liquid-glass-stream-overlay
//
//  Created by Rodney Mackey on 04.11.2025.
//

import Foundation
import SwiftUI

// Модель эмоута Twitch (Helix chat/emotes)
/// Структура для парсинга твитч эмоут
struct Message: Equatable, Identifiable {
    let id: UUID
    let sender: String
    let text: String
    let badges: [(String, String)]
    let senderColor: Color?
    let badgeViewData: [BadgeViewData]

    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id &&
        lhs.sender == rhs.sender &&
        lhs.text == rhs.text &&
        lhs.badges.elementsEqual(rhs.badges, by: { $0.0 == $1.0 && $0.1 == $1.1 }) &&
        lhs.senderColor == rhs.senderColor &&
        lhs.badgeViewData == rhs.badgeViewData
    }
}
