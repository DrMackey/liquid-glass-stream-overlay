// TwitchChatManager.swift
// Менеджер чата Twitch + утилиты отображения сообщений, эмоута и информации о стриме

// MARK: - Импорты фреймворков (UI, сеть, изображения)
import SwiftUI
import Combine
import Foundation
import Network
import SDWebImageSwiftUI
import AppKit

// Глобальная функция: получение идентификатора канала по логину через Helix /users
func fetchChannelId(login: String) async throws -> String {
    return try await TwitchChatManager.sharedChannelId(login: login)
}

class Config {
    static let shared = Config()

    var TwitchChannel: String {
        return Bundle.main.infoDictionary?["TWITCH_CHANNEL"] as? String ?? ""
    }

    var TwitchHelixClientID: String {
        return Bundle.main.infoDictionary?["TWITCH_HELIX_CLIENT_ID"] as? String ?? ""
    }

    var TwitchHelixBearerToken: String {
        return Bundle.main.infoDictionary?["TWITCH_HELIX_BEARER_TOKEN"] as? String ?? ""
    }
}

//let TWITCH_HELIX_BASE_URL = "https://api.twitch.tv/helix"
let TWITCH_HELIX_BASE_URL = "http://localhost:8080/mock"

//Авторизационные данные для основы
//let TWITCH_CHANNEL = Config.shared.TwitchChannel
//let TWITCH_HELIX_CLIENT_ID = Config.shared.TwitchHelixClientID
//let TWITCH_HELIX_BEARER_TOKEN = Config.shared.TwitchHelixBearerToken

//Дебаг режим
let TWITCH_CHANNEL = Config.shared.TwitchChannel
let TWITCH_HELIX_CLIENT_ID = "xbhqka8dire6qufn4xttrrcylalpil"
let TWITCH_HELIX_BEARER_TOKEN = "iigl9icsx0kyc973amwr1rb4lyo699"

// MARK: - Модель частей сообщения (текст/эмоут)
enum MessagePart: Hashable {
    case text(String)
    case emote(name: String, url: String, animated: Bool)
}

// MARK: - Основной менеджер чата Twitch
final class TwitchChatManager: ObservableObject {

    // MARK: - Константы
    enum Constants {
        static let maxMessages = 20
        static let streamInfoInterval: UInt64 = 30 * 1_000_000_000
        static let notificationDisplayTime: TimeInterval = 5
        static let maxReconnectDelay: TimeInterval = 60
        static let keepaliveTimeout: TimeInterval = 15  // Twitch гарантирует keepalive каждые 10с
    }

    // MARK: - Кэш channelId
    private static var cachedChannelId: String? = nil
    private static var channelIdLock = NSLock()
    private static var channelIdContinuations: [CheckedContinuation<String, Error>] = []
    private static var channelIdFetchInProgress = false

    private var cancellables = Set<AnyCancellable>()

    // получения ID канала Twitch с дедупликацией запросов и запуска Task
    static func sharedChannelId(login: String) async throws -> String {
        // Быстрый путь без блокировки
        if let id = cachedChannelId { return id }

        return try await withCheckedThrowingContinuation { continuation in
            channelIdLock.lock()
            defer { channelIdLock.unlock() }

            // Повторная проверка под блокировкой
            if let id = cachedChannelId {
                continuation.resume(returning: id)
                return
            }

            channelIdContinuations.append(continuation)

            guard !channelIdFetchInProgress else { return }
            channelIdFetchInProgress = true

            Task {
                do {
                    let url = URL(string: "\(TWITCH_HELIX_BASE_URL)/users?login=\(login.lowercased())")!
                    var req = URLRequest(url: url)
                    req.addValue("Bearer \(TWITCH_HELIX_BEARER_TOKEN)", forHTTPHeaderField: "Authorization")
                    req.addValue(TWITCH_HELIX_CLIENT_ID, forHTTPHeaderField: "Client-Id")
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    if let http = resp as? HTTPURLResponse {
                        print("[TwitchChat] helix/users status: \(http.statusCode)")
                    }
                    struct UsersResponse: Decodable {
                        struct User: Decodable { let id: String }
                        let data: [User]
                    }
                    let decoded = try JSONDecoder().decode(UsersResponse.self, from: data)
                    guard let id = decoded.data.first?.id else { throw URLError(.badServerResponse) }

                    channelIdLock.lock()
                    cachedChannelId = id
                    let waiting = channelIdContinuations
                    channelIdContinuations.removeAll()
                    channelIdFetchInProgress = false
                    channelIdLock.unlock()

                    waiting.forEach { $0.resume(returning: id) }
                } catch {
                    channelIdLock.lock()
                    let waiting = channelIdContinuations
                    channelIdContinuations.removeAll()
                    channelIdFetchInProgress = false
                    channelIdLock.unlock()

                    waiting.forEach { $0.resume(throwing: error) }
                }
            }
        }
    }

    // MARK: - Published состояния
    @Published var lastMessage: Message?
    @Published var messages: [Message] = []
    @Published var notifications: [Notification] = []
    @Published var allBadgeImages: [String: [String: String]] = [:]
    @Published var emoteMap: [String: String] = [:]
    @Published var stvEmoteMap: [String: String] = [:]
    @Published var stvChannelEmoteMap: [String: (url: String, animated: Bool)] = [:]
    @Published var bttvGlobalMap: [String: String] = [:]
    @Published var bttvChannelMap: [String: String] = [:]
    @Published var streamTitle: String = ""
    @Published var categoryName: String = ""
    @Published var categoryImageURL: URL? = nil
    @Published var isConnected: String = ""

    // MARK: - Приватные свойства
     var channelId: String? = nil
    private var lastDisplayTime: Date = .distantPast
    private var pendingMessage: Message? = nil
    private var displayTimer: Timer?
    private var streamInfoTask: Task<Void, Never>?

    // MARK: - EventSub (WebSocket)
    private var eventSubSessionId: String?
    private var eventSubSocket: EventSubSocketClient?
    private var eventSubConsumerTask: Task<Void, Never>?
    private let eventSubURL = URL(string: "ws://127.0.0.1:8080/ws")!

    // MARK: - Init
    init() {
        streamInfoTask = Task { [weak self] in
            await self?.runStreamInfoLoop()
        }
        let socket = EventSubSocketClient(
            url: eventSubURL,
            keepaliveTimeout: Constants.keepaliveTimeout,
            maxReconnectDelay: Constants.maxReconnectDelay,
            onStateChange: { [weak self] event in self?.handleStateChange(event) }
        )
        eventSubSocket = socket
        consumeEventSubEvents(from: socket)
        socket.start()
        setupNotificationsAutoClear(
                    notificationDisplayTime: 5,
                    manager: self,
                    cancellables: &cancellables
                )
    }
    
    // MARK: - Stop
    func stop() {
        EventSubLog.info("stop()")
        eventSubConsumerTask?.cancel()
        eventSubConsumerTask = nil
        eventSubSocket?.stop()
        eventSubSocket = nil
        streamInfoTask?.cancel()
        streamInfoTask = nil
    }

    // MARK: - Helix-заголовки
    func addHelixHeaders(_ request: inout URLRequest) {
        request.addValue("Bearer \(TWITCH_HELIX_BEARER_TOKEN)", forHTTPHeaderField: "Authorization")
        request.addValue(TWITCH_HELIX_CLIENT_ID, forHTTPHeaderField: "Client-Id")
    }

    // MARK: - Badge helpers
    func badgeViews(from badges: [(String, String)], badgeUrlMap: [String: [String: String]]) -> [BadgeViewData] {
        badges.map { (set, version) in
            let url = badgeUrlMap[set]?[version].flatMap { URL(string: $0) }
            return BadgeViewData(set: set, version: version, url: url)
        }
    }

    // MARK: - Загрузка эмоутов
    func loadGlobalEmotes() async {
        // Все источники загружаем параллельно
        async let stv: Void = load7TVEmotes(manager: self)
        async let stvChannel: Void = load7TVChannelEmotes(channelLogin: TWITCH_CHANNEL, manager: self)
        async let bttvGlobal: Void = loadBTTVGlobalEmotes(manager: self)
        async let bttvChannel: Void = loadBTTVChannelEmotes(channelLogin: TWITCH_CHANNEL, manager: self)
        async let twitchGlobal: Void = loadTwitchGlobalEmotes(manager: self)
        _ = await (stv, stvChannel, bttvGlobal, bttvChannel, twitchGlobal)
    }

    // MARK: - EventSub подписка
    private func subscribeToEventSub(sessionId: String) async {
        var targetUserId = self.channelId ?? ""
        if targetUserId.isEmpty {
            targetUserId = (try? await TwitchChatManager.sharedChannelId(login: TWITCH_CHANNEL)) ?? ""
        }
        guard !targetUserId.isEmpty else {
            EventSubLog.info("Не удалось определить user_id для подписки")
            return
        }
        
    // https://dev.twitch.tv/docs/eventsub/eventsub-subscription-types/
        let desiredTypes = [
            "channel.channel_points_custom_reward_redemption.add", // Поддержано | Использование баллов канала
            "channel.chat.message", // Поддержано | Любой пользователь получает сообщение в чат
            "channel.chat.clear", // Чат был очищен
            "channel.chat.clear_user_messages", // Были удалены все сообщения от конкретного пользователя
            "channel.chat.message_delete", // Конкретное сообщение было удалено
            "channel.chat.notification", // уведомление при возникновении события в чате, например, при подписке на канал или при получении подарка в виде подписки
            "channel.follow", // Бесплатная подписка на канал
            "channel.subscribe", // Платная подписка на канал, без учета повторных подписок
            "channel.subscription.end", // Окончание подписки на указанный канал
            "channel.subscription.gift", // Подарочная платная подписка
            "channel.subscription.message", // Уведомлении при повторной платной подписке
            "channel.raid", // Рейд на канал
            "channel.goal.progress", // Прогресс об изменениях в цели
            "channel.goal.end", // Завершение цели
            "channel.update", // Обовление данных о трансляции (название, категория)
            "channel.ban", // Пользователь был заблокирован
            "channel.unban", // Пользователь был разблокирован
            "channel.vip.add", // Был добавлен VIP
            "channel.vip.remove", // VIP Был удален
            "channel.hype_train.begin", // Старт хайптрейна
            "channel.hype_train.progress", // Хайптрейн набирает обороты
            "channel.hype_train.end", // Завершение хайптрейна
        ]

        // Получаем активные подписки
        var activeTypes = Set<String>()
        do {
            let getURL = URL(string: "\(TWITCH_HELIX_BASE_URL)/eventsub/subscriptions?status=enabled")!
            var getReq = URLRequest(url: getURL)
            getReq.httpMethod = "GET"
            addHelixHeaders(&getReq)
            let (getData, _) = try await URLSession.shared.data(for: getReq)
            struct GetRoot: Decodable { struct Item: Decodable { let type: String? }; let data: [Item]? }
            if let decoded = try? JSONDecoder().decode(GetRoot.self, from: getData) {
                decoded.data?.compactMap { $0.type }.forEach { activeTypes.insert($0) }
            }
        } catch {
            EventSubLog.info("GET subscriptions error: \(error)")
        }

        // Подписываемся на недостающие типы
        for t in desiredTypes where !activeTypes.contains(t) {
            do {
                let url = URL(string: "\(TWITCH_HELIX_BASE_URL)/eventsub/subscriptions")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                addHelixHeaders(&req)
                req.addValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try buildEventSubSubscriptionBody(sessionId: sessionId, userId: targetUserId, overrideType: t)
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse {
                    EventSubLog.debug("subscribe status for type=\(t): \(http.statusCode)")
                }
            } catch {
                EventSubLog.info("subscribe error for type=\(t): \(error)")
            }
        }
    }
}

// MARK: - EventSub WebSocket
extension TwitchChatManager {

    // MARK: - Обработка событий транспорта
    /// Переводит события жизненного цикла соединения в состояние UI.
    private func handleStateChange(_ event: EventSubSocketClient.StateEvent) {
        switch event {
        case .connecting(let attempt):
            EventSubLog.debug("Подключаемся (попытка \(attempt))…")
            DispatchQueue.main.async { self.isConnected = "Подключение…" }

        case .connected:
            DispatchQueue.main.async { self.isConnected = "Подключено" }

        case .reconnectingIn(let seconds, let attempt):
            if seconds == 0 {
                DispatchQueue.main.async { self.isConnected = "Переподключение…" }
            } else {
                DispatchQueue.main.async { self.isConnected = "Переподключение через \(seconds)с…" }
            }
            EventSubLog.debug("Переподключение: попытка \(attempt), задержка \(seconds)с")

        case .failed(let error):
            DispatchQueue.main.async { self.isConnected = "Ошибка соединения" }
            EventSubLog.debug("Ошибка соединения: \(error)")

        case .stopped:
            EventSubLog.debug("Сокет остановлен")
        }
    }

    // MARK: - Поток событий EventSub
    /// Единственное место, где менеджер читает события сокета.
    ///
    /// Таск наследует изоляцию главного актора, поэтому `apply` меняет
    /// `@Published`-свойства без гонок и без хопов через `DispatchQueue`.
    private func consumeEventSubEvents(from socket: EventSubSocketClient) {
        eventSubConsumerTask?.cancel()
        eventSubConsumerTask = Task { [weak self] in
            for await event in socket.events {
                guard let self else { return }
                self.apply(EventSubRouter.actions(for: event))
            }
        }
    }

    /// Применяет намерения роутера. Новый случай действия заставит компилятор
    /// спросить, что с ним делать, — это защита от молчаливых потерь событий.
    private func apply(_ actions: [EventSubRouter.Action]) {
        for action in actions {
            switch action {
            case .subscribe(let sessionId):
                eventSubSessionId = sessionId
                // Успешное подключение — сбрасываем счётчик попыток
                eventSubSocket?.resetReconnectBackoff()
                EventSubLog.debug("session_welcome: session_id=\(sessionId)")
                Task { await self.subscribeToEventSub(sessionId: sessionId) }

            case .reconnect:
                // Twitch просит переподключиться к новому URL
                requestImmediateReconnect()

            case .chat(let chat):
                let badgePairs = chat.badgePairs
                appendChatMessage(Message(
                    sender: chat.chatterUserName,
                    text: chat.text,
                    badges: badgePairs,
                    senderColor: chat.colorHex.flatMap { colorFromHex($0) },
                    badgeViewData: badgeViews(from: badgePairs, badgeUrlMap: allBadgeImages)))

            case .notice(let event):
                appendNotice(event)

            case .revoke(let subscriptionType):
                EventSubLog.info("Подписка \(subscriptionType) отозвана")
            }
        }
    }

    /// Сообщение чата: пустые цвета и неизвестные бейджи отсеиваются декодером.
    private func appendChatMessage(_ message: Message) {
        lastMessage = message
        messages.append(message)
        trimMessages()
    }

    /// Событие прочей подписки: и в список сообщений, и в баннер уведомлений.
    private func appendNotice(_ event: EventSubNotice) {
        let id = event.messageId.flatMap { UUID(uuidString: $0) } ?? UUID()
        let sender = event.userName ?? "eventsub"
        // Заголовка может не быть (например, у `channel.subscription.gift`).
        // Раньше fallback'ом служил сырой JSON, но типизированная модель его не
        // хранит, поэтому показываем тип подписки — он информативнее.
        let body = event.title.flatMap { $0.isEmpty ? nil : $0 } ?? event.subscriptionType
        let text = "Получена награда — \(body)"
        let badgeViewData = badgeViews(from: [], badgeUrlMap: allBadgeImages)

        notifications.append(Notification(id: id, sender: sender, text: text,
                                          badges: [], senderColor: .gray, badgeViewData: badgeViewData))
        messages.append(Message(id: UUID(), sender: sender, text: text,
                                badges: [], senderColor: .gray, badgeViewData: badgeViewData))
        trimMessages()
    }

    private func trimMessages() {
        if messages.count > Constants.maxMessages {
            messages.removeFirst(messages.count - Constants.maxMessages)
        }
    }

    private func requestImmediateReconnect() {
        eventSubSocket?.scheduleReconnect(immediately: true)
    }


    // MARK: - Билдер тела подписки
    private func buildEventSubSubscriptionBody(sessionId: String, userId: String) throws -> Data {
        try buildEventSubSubscriptionBody(sessionId: sessionId, userId: userId,
                                          overrideType: "channel.channel_points_custom_reward_redemption.add")
    }

    private func buildEventSubSubscriptionBody(sessionId: String, userId: String, overrideType: String) throws -> Data {
        struct Body: Encodable {
            struct Condition: Encodable { let broadcaster_user_id: String; let moderator_user_id: String; let user_id: String }
            struct Transport: Encodable { let method: String; let session_id: String }
            let type: String
            let version: String
            let condition: Condition
            let transport: Transport
        }
        return try JSONEncoder().encode(Body(
            type: overrideType,
            version: "1",
            condition: .init(broadcaster_user_id: userId, moderator_user_id: "84011517", user_id: "84011517"),
            transport: .init(method: "websocket", session_id: sessionId)
        ))
    }
}



//MARK: - Convenience inits
extension Message {
    init(sender: String, text: String, badges: [(String, String)], senderColor: Color?, badgeViewData: [BadgeViewData]) {
        self.id = UUID()
        self.sender = sender
        self.text = text
        self.badges = badges
        self.senderColor = senderColor
        self.badgeViewData = badgeViewData
    }
}

extension Notification {
    init(sender: String, text: String, badges: [(String, String)], senderColor: Color?, badgeViewData: [BadgeViewData]) {
        self.id = UUID()
        self.sender = sender
        self.text = text
        self.badges = badges
        self.senderColor = senderColor
        self.badgeViewData = badgeViewData
    }
}


