// EventSubSocketClient.swift
// Транспорт EventSub WebSocket: соединение, приём сообщений, keepalive и переподключение

import Foundation

/// Владеет жизненным циклом WebSocket-соединения с Twitch EventSub.
///
/// Клиент ничего не знает о подписках и UI. Входящие сообщения он декодирует
/// сам и отдаёт через `events` уже типизированными `EventSubEvent`, поэтому
/// вызывающий код никогда не работает со строкой JSON. Отдельно через
/// `onStateChange` приходят события жизненного цикла соединения.
final class EventSubSocketClient {

    /// События жизненного цикла соединения.
    enum StateEvent {
        /// Начата попытка подключения. `attempt` — 1-based номер попытки.
        case connecting(attempt: Int)
        /// Соединение установлено, получено первое сообщение.
        case connected
        /// Соединение потеряно, назначена повторная попытка.
        case reconnectingIn(seconds: Int, attempt: Int)
        /// Соединение завершилось ошибкой.
        case failed(String)
        /// Клиент остановлен.
        case stopped
    }

    /// Поток типизированных событий Twitch.
    ///
    /// Поток живёт всё время жизни клиента и переживает переподключения:
    /// переподключение — внутреннее дело транспорта, потребитель о нём не знает.
    /// Буфер ограничен и при переполнении вытесняет самые старые события —
    /// устаревшее сообщение чата показывать бессмысленно.
    let events: AsyncStream<EventSubEvent>
    private let eventContinuation: AsyncStream<EventSubEvent>.Continuation

    private let keepaliveTimeout: TimeInterval
    private let maxReconnectDelay: TimeInterval
    private let onStateChange: (StateEvent) -> Void

    private let urlSession = URLSession(configuration: .default)

    /// Адрес, к которому клиент подключается.
    ///
    /// Обычно это исходный URL, но Twitch присылает новый адрес в
    /// `session_reconnect`, и по протоколу к нему нужно перейти, иначе сессия
    /// завершится по таймауту. Поэтому адрес сменный.
    private var url: URL
    private var task: URLSessionWebSocketTask?
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var keepaliveTimer: Timer?

    init(
        url: URL,
        keepaliveTimeout: TimeInterval,
        maxReconnectDelay: TimeInterval,
        onStateChange: @escaping (StateEvent) -> Void
    ) {
        self.url = url
        self.keepaliveTimeout = keepaliveTimeout
        self.maxReconnectDelay = maxReconnectDelay
        self.onStateChange = onStateChange

        var continuation: AsyncStream<EventSubEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(256)) { continuation = $0 }
        self.eventContinuation = continuation
    }

    deinit {
        eventContinuation.finish()
    }

    /// Адрес, к которому клиент подключается прямо сейчас.
    ///
    /// Отличается от исходного после `session_reconnect`. Существует для тестов:
    /// сам сокет нигде не читает это свойство после `start()`.
    var currentURL: URL { url }

    /// Twitch присылает keepalive каждые ~10 секунд, поэтому молчание дольше
    /// `keepaliveTimeout` означает, что соединение мертво.
    private var keepaliveDeadline: TimeInterval { keepaliveTimeout + 5 }

    // MARK: - Запуск и остановка

    /// Открывает соединение и начинает принимать сообщения.
    func start() {
        // Отменяем отложенное переподключение, если оно есть
        reconnectTask?.cancel()
        reconnectTask = nil

        // Не дублируем активное соединение
        if let task {
            switch task.state {
            case .running, .suspended: return
            default: break
            }
        }

        EventSubLog.debug("Подключаемся (попытка \(reconnectAttempt + 1))…")
        onStateChange(.connecting(attempt: reconnectAttempt + 1))

        let task = urlSession.webSocketTask(with: url)
        self.task = task
        task.resume()
        resetKeepaliveTimer()
        listen()
    }

    /// Закрывает соединение и отменяет все отложенные действия.
    func stop() {
        cancelKeepaliveTimer()
        reconnectTask?.cancel()
        reconnectTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onStateChange(.stopped)
    }

    /// Сбрасывает счётчик попыток — вызывается после успешного `session_welcome`.
    func resetReconnectBackoff() {
        reconnectAttempt = 0
    }

    /// Переподключается по адресу из `session_reconnect`.
    ///
    /// Twitch требует уйти на `reconnect_url`: старая сессия живёт ограниченное
    /// время, и подписки переезжают на новую сессию сами — заново создавать их
    /// не нужно. Если адрес не пришёл или не разбирается, клиент возвращается
    /// к исходному URL.
    func reconnect(to newURL: URL?) {
        if let newURL {
            EventSubLog.info("session_reconnect: переходим на новый URL сессии")
            url = newURL
        }
        scheduleReconnect(immediately: true)
    }

    /// Отправляет ping, чтобы проверить живость соединения.
    func sendPing() {
        task?.sendPing { [weak self] error in
            if let error { EventSubLog.info("ping/pong send error: \(error)") }
            _ = self
        }
    }

    // MARK: - Keepalive

    private func resetKeepaliveTimer() {
        cancelKeepaliveTimer()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.keepaliveTimer = Timer.scheduledTimer(
                withTimeInterval: self.keepaliveDeadline,
                repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }
                EventSubLog.info("Keepalive timeout — переподключаемся")
                self.scheduleReconnect()
            }
        }
    }

    private func cancelKeepaliveTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.keepaliveTimer?.invalidate()
            self?.keepaliveTimer = nil
        }
    }

    // MARK: - Приём сообщений

    private func listen() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                EventSubLog.info("receive error: \(error)")
                self.onStateChange(.failed(error.localizedDescription))
                self.scheduleReconnect()

            case .success(let message):
                // Любое входящее сообщение сбрасывает таймер keepalive
                self.resetKeepaliveTimer()
                self.onStateChange(.connected)
                self.emit(message)

                // Продолжаем слушать только если соединение активно
                if let task = self.task, task.state == .running {
                    self.listen()
                }
            }
        }
    }

    /// Разбирает входящее сообщение и кладёт типизированное событие в поток.
    ///
    /// Декодирование живёт здесь, на границе сокета: дальше по коду строки JSON
    /// уже не ходят, поэтому повторный разбор исключён by construction.
    private func emit(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text):
            EventSubLog.debug("<- \(text)")
            guard let encoded = text.data(using: .utf8) else { return }
            data = encoded
        case .data(let received):
            data = received
        @unknown default:
            return
        }

        do {
            eventContinuation.yield(try JSONDecoder().decode(EventSubEvent.self, from: data))
        } catch {
            EventSubLog.info("Не удалось разобрать сообщение EventSub: \(error)")
        }
    }

    // MARK: - Переподключение с exponential backoff

    /// Задержка перед повторной попыткой: 1, 2, 4, 8, 16, 32 секунд, затем потолок.
    static func backoffDelay(attempt: Int, maxDelay: TimeInterval) -> TimeInterval {
        min(pow(2.0, Double(attempt)), maxDelay)
    }

    /// Планирует переподключение с нарастающей задержкой.
    func scheduleReconnect(immediately: Bool = false) {
        cancelKeepaliveTimer()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        reconnectTask?.cancel()

        let delay: TimeInterval
        let attempt: Int
        if immediately {
            delay = 0
            attempt = reconnectAttempt + 1
        } else {
            delay = Self.backoffDelay(attempt: reconnectAttempt, maxDelay: maxReconnectDelay)
            reconnectAttempt += 1
            attempt = reconnectAttempt
            EventSubLog.info("Следующая попытка через \(Int(delay))с (попытка \(attempt))")
        }

        onStateChange(.reconnectingIn(seconds: Int(delay), attempt: attempt))

        reconnectTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }
}