// EventSubLog.swift
// Логирование EventSub с переключателем для горячего пути

import Foundation
import os

/// Логгер для событий EventSub.
///
/// Покадровая печать каждого сообщения чата на горячем пути заметно нагружает
/// приложение, поэтому в Release-сборках она отключена по умолчанию.
/// Включается через флаг `verbose`, который можно поднять на время отладки.
enum EventSubLog {

    /// Текущий уровень детализации логов.
    ///
    /// По умолчанию полный лог включён в Debug и выключен в Release.
    /// Требует `nonisolated(unsafe)`, так как обращения идут из callback'ов сокета
    /// вне главного актора.
    nonisolated(unsafe) static var verbose: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Системный логгер.
    ///
    /// `nonisolated` обязателен: `debug` вызывается из callback'ов сокета вне
    /// главного актора, а без аннотации константа унаследовала бы изоляцию
    /// модуля. `Logger` — `Sendable`, поэтому это безопасно.
    nonisolated static let logger = Logger(
        subsystem: "com.drmackey.liquid-glass-stream-overlay",
        category: "EventSub"
    )

    /// Печатает сообщение только если подробный лог включён.
    nonisolated static func debug(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        let text = message()
        logger.debug("\(text, privacy: .public)")
    }

    /// Печатает сообщение всегда — для ошибок и важных переходов состояния.
    nonisolated static func info(_ message: @autoclosure () -> String) {
        print("[EventSub] \(message())")
    }
}