// EventSubSocketClientTests.swift
// Тесты транспортного слоя EventSub, не требующие реального сокета

import Foundation
import Testing

@testable import Liquid_Glass_Stream_Overlay

@Suite("EventSub: транспорт WebSocket")
struct EventSubSocketClientTests {

    @Test("Backoff растёт экспоненциально до потолка")
    func backoffGrowsExponentially() {
        let max: TimeInterval = 60

        #expect(EventSubSocketClient.backoffDelay(attempt: 0, maxDelay: max) == 1)
        #expect(EventSubSocketClient.backoffDelay(attempt: 1, maxDelay: max) == 2)
        #expect(EventSubSocketClient.backoffDelay(attempt: 2, maxDelay: max) == 4)
        #expect(EventSubSocketClient.backoffDelay(attempt: 3, maxDelay: max) == 8)
        #expect(EventSubSocketClient.backoffDelay(attempt: 5, maxDelay: max) == 32)
    }

    @Test("Backoff не превышает потолок")
    func backoffIsCapped() {
        let max: TimeInterval = 60

        #expect(EventSubSocketClient.backoffDelay(attempt: 6, maxDelay: max) == 60)
        #expect(EventSubSocketClient.backoffDelay(attempt: 20, maxDelay: max) == 60)
    }

    @Test("Start сообщает о попытке подключения и не дублирует активную сессию")
    func startReportsConnecting() {
        let recorder = EventRecorder()
        let client = EventSubSocketClient(
            url: URL(string: "ws://127.0.0.1:1/ws")!,
            keepaliveTimeout: 15,
            maxReconnectDelay: 60,
            onStateChange: { recorder.append($0) }
        )

        client.start()

        #expect(recorder.connectingAttempts == [1])
        client.stop()
        #expect(recorder.containsStopped)
    }

    @Test("Stop отменяет отложенное переподключение")
    func stopCancelsPendingReconnect() {
        let recorder = EventRecorder()
        let client = EventSubSocketClient(
            url: URL(string: "ws://127.0.0.1:1/ws")!,
            keepaliveTimeout: 15,
            maxReconnectDelay: 60,
            onStateChange: { recorder.append($0) }
        )

        client.start()
        client.scheduleReconnect()
        client.stop()

        #expect(recorder.containsStopped)
        #expect(recorder.reconnects.contains { $0.seconds == 1 })
    }

    @Test("Reconnect переводит клиента на URL новой сессии")
    func reconnectSwitchesURL() {
        let recorder = EventRecorder()
        let original = URL(string: "ws://127.0.0.1:1/ws")!
        let client = EventSubSocketClient(
            url: original,
            keepaliveTimeout: 15,
            maxReconnectDelay: 60,
            onStateChange: { recorder.append($0) }
        )

        #expect(client.currentURL == original)

        client.reconnect(to: URL(string: "wss://eventsub.wss.twitch.tv/ws"))

        #expect(client.currentURL == URL(string: "wss://eventsub.wss.twitch.tv/ws"))
        // Новая сессия не должна ждать backoff: подписки на старой уже не работают.
        #expect(recorder.reconnects.contains { $0.seconds == 0 })
        client.stop()
    }

    @Test("Reconnect без URL остаётся на прежнем адресе")
    func reconnectWithoutURLKeepsOriginal() {
        let recorder = EventRecorder()
        let original = URL(string: "ws://127.0.0.1:1/ws")!
        let client = EventSubSocketClient(
            url: original,
            keepaliveTimeout: 15,
            maxReconnectDelay: 60,
            onStateChange: { recorder.append($0) }
        )

        client.reconnect(to: nil)

        #expect(client.currentURL == original)
        client.stop()
    }
}

// MARK: - Хелпер

/// Собирает события транспорта для проверки.
private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [EventSubSocketClient.StateEvent] = []

    func append(_ event: EventSubSocketClient.StateEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    var all: [EventSubSocketClient.StateEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    var connectingAttempts: [Int] {
        all.compactMap {
            if case .connecting(let attempt) = $0 { return attempt }
            return nil
        }
    }

    var reconnects: [(seconds: Int, attempt: Int)] {
        all.compactMap {
            if case .reconnectingIn(let seconds, let attempt) = $0 { return (seconds, attempt) }
            return nil
        }
    }

    var containsStopped: Bool {
        all.contains { if case .stopped = $0 { return true } else { return false } }
    }
}