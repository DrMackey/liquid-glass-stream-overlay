// EventSubFixtures.swift
// Загрузка JSON-фикстур из bundle тестов

import Foundation

@testable import Liquid_Glass_Stream_Overlay

/// Маркер для получения bundle'а тестового таргета.
private final class BundleToken {}

/// Доступ к JSON-фикстурам сообщений EventSub.
enum EventSubFixtures {

    /// Загружает фикстуру по имени файла (без расширения `.json`).
    ///
    /// - Returns: Сырые данные фикстуры.
    /// - Throws: Ошибка, если файл не найден в bundle теста.
    static func data(named name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: "json") else {
            throw FixtureError.notFound(name)
        }
        return try Data(contentsOf: url)
    }

    /// Загружает фикстуру и разбирает её в JSON-дерево.
    static func json(named name: String) throws -> Any {
        try JSONSerialization.jsonObject(with: try data(named: name))
    }

    /// Загружает фикстуру как строку.
    static func string(named name: String) throws -> String {
        String(decoding: try data(named: name), as: UTF8.self)
    }

    /// Загружает фикстуру и разбирает её одним проходом в `EventSubEvent`.
    static func event(named name: String) throws -> EventSubEvent {
        try JSONDecoder().decode(EventSubEvent.self, from: try data(named: name))
    }

    enum FixtureError: Error, CustomStringConvertible {
        case notFound(String)

        var description: String {
            switch self {
            case .notFound(let name):
                return "Фикстура '\(name).json' не найдена в bundle тестов"
            }
        }
    }
}