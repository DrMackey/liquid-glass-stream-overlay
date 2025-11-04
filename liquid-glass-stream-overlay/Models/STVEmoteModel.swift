//
//  STVEmoteModel.swift
//  liquid-glass-stream-overlay
//
//  Created by Rodney Mackey on 04.11.2025.
//

import Foundation

// Модель 7TV эмоута для декодирования API и генерации URL
/// Структура для парсинга одной эмоуты 7TV
struct STVEmote: Decodable, Hashable {
    let name: String
    let id: String
    let host: Host
    struct Host: Decodable, Hashable {
        let url: String
        let files: [File]
        struct File: Decodable, Hashable {
            let name: String
            let format: String
            let width: Int?
            let height: Int?
        }
    }
    // Формирует прямой URL до файла эмоута указанного формата
    /// Генерация URL для разных размеров и форматов
    func url(size: String, format: String) -> String? {
        // Пример URL: https://cdn.7tv.app/emote/{id}/{size}
        let base = host.url.hasPrefix("http") ? host.url : ("https:" + host.url)
        // Обычно webp
        let f = host.files.first { $0.format.uppercased() == format }
        guard let file = f else { return nil }
        return "\(base)/\(file.name)"
    }
}
