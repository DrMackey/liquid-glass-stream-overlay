//
//  EmoteModel.swift
//  liquid-glass-stream-overlay
//
//  Created by Rodney Mackey on 04.11.2025.
//

import Foundation

// Модель эмоута Twitch (Helix chat/emotes)
/// Структура для парсинга твитч эмоут
struct Emote: Decodable, Hashable {
    let id: String
    let name: String
    let images: Images
    let format: [String]?
    struct Images: Decodable, Hashable {
        let url_1x: String
    }
}
