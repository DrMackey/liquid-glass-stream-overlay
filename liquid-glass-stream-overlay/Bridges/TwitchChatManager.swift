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

let TWITCH_CHANNEL = Config.shared.TwitchChannel
let TWITCH_HELIX_CLIENT_ID = Config.shared.TwitchHelixClientID
let TWITCH_HELIX_BEARER_TOKEN = Config.shared.TwitchHelixBearerToken

// MARK: - Модель частей сообщения (текст/эмоут)
enum MessagePart: Hashable {
    case text(String)
    case emote(name: String, url: String, animated: Bool)
}

// MARK: - Отображение эмоутов (анимированные и статичные)
struct EmoteImageView: View {
    let url: URL
    let size: CGFloat
    let animated: Bool

    var body: some View {
        Group {
            let ext = url.pathExtension.lowercased()
            if animated || ext == "webp" || ext == "gif" {
                AnimatedImage(url: url)
                    .onFailure { error in print("ОШИБКА \(error)") }
                    .resizable()
                    .indicator(.activity)
                    .transition(.fade)
                    .scaledToFit()
                    .frame(height: size)
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(width: 30, height: 30)
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size, height: size)
                    case .failure:
                        Text(":)").frame(width: size, height: size)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }
}

// macOS-обёртка для отображения GIF через NSImageView
struct AnimatedGIFView: NSViewRepresentable {
    let data: Data
    let size: CGFloat

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        imageView.canDrawSubviewsIntoLayer = true
        imageView.animates = true
        if let image = NSImage(data: data) { imageView.image = image }
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: size),
            imageView.heightAnchor.constraint(equalToConstant: size)
        ])
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = NSImage(data: data)
    }
}

struct BadgeViewData: Identifiable, Hashable, Equatable {
    let id = UUID()
    let set: String
    let version: String
    let url: URL?
}

// MARK: - Основной менеджер чата Twitch
final class TwitchChatManager: ObservableObject {

    // MARK: - Константы
    private enum Constants {
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
                    let url = URL(string: "https://api.twitch.tv/helix/users?login=\(login.lowercased())")!
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

    // MARK: - Модели данных
    struct BadgeInfo: Hashable {
        let set: String
        let version: String
        let imageUrl: String
    }

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

    struct Notification: Equatable, Identifiable {
        let id: UUID
        let sender: String
        let text: String
        let badges: [(String, String)]
        let senderColor: Color?
        let badgeViewData: [BadgeViewData]

        static func == (lhs: Notification, rhs: Notification) -> Bool {
            lhs.id == rhs.id &&
            lhs.sender == rhs.sender &&
            lhs.text == rhs.text &&
            lhs.badges.elementsEqual(rhs.badges, by: { $0.0 == $1.0 && $0.1 == $1.1 }) &&
            lhs.senderColor == rhs.senderColor &&
            lhs.badgeViewData == rhs.badgeViewData
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
    private(set) var channelId: String? = nil
    private var lastDisplayTime: Date = .distantPast
    private var pendingMessage: Message? = nil
    private var displayTimer: Timer?
    private var streamInfoTask: Task<Void, Never>?

    // MARK: - EventSub (WebSocket)
    private var eventSubWebSocketTask: URLSessionWebSocketTask?
    private var eventSubSessionId: String?
    private let eventSubURL = URL(string: "wss://eventsub.wss.twitch.tv/ws")!
    private let urlSession = URLSession(configuration: .default)

    /// Счётчик и задержка для exponential backoff при переподключении
    private var reconnectAttempt: Int = 0
    private var reconnectTask: Task<Void, Never>?

    /// Таймер для отслеживания keepalive — если Twitch не присылает keepalive/уведомление, переподключаемся
    private var keepaliveTimer: Timer?

    // MARK: - Init
    init() {
        streamInfoTask = Task { [weak self] in
            await self?.runStreamInfoLoop()
        }
        startEventSubWebSocket()
        setupNotificationsAutoClear()
    }

    // MARK: - Автоочистка уведомлений
    private func setupNotificationsAutoClear() {
        var lastKnown: [Notification] = []

        $notifications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] current in
                guard let self = self else { return }
                let lastIds = Set(lastKnown.map { $0.id })
                let newOnes = current.filter { !lastIds.contains($0.id) }

                for notif in newOnes {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.notificationDisplayTime) { [weak self] in
                        self?.notifications.removeAll { $0.id == notif.id }
                    }
                }
                lastKnown = current
            }
            .store(in: &cancellables)
    }

    // MARK: - Helix-заголовки
    private func addHelixHeaders(_ request: inout URLRequest) {
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

    // MARK: - Добавление сообщения в UI
    private func setLastMessageThrottled(_ message: Message) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastMessage = message
            self.messages.append(message)
            if self.messages.count > Constants.maxMessages {
                self.messages.removeFirst(self.messages.count - Constants.maxMessages)
            }
        }
    }

    // MARK: - Stop
    func stop() {
        print("[TwitchChat] stop()")
        cancelKeepaliveTimer()
        reconnectTask?.cancel()
        reconnectTask = nil
        eventSubWebSocketTask?.cancel(with: .goingAway, reason: nil)
        eventSubWebSocketTask = nil
        streamInfoTask?.cancel()
        streamInfoTask = nil
    }

    // MARK: - Загрузка бейджей
    func loadAllBadges(channelLogin: String) async {
        // Общие типы для парсинга бейджей
        struct BadgeVersion: Decodable { let id: String; let image_url_2x: String? }
        struct BadgeSet: Decodable { let set_id: String; let versions: [BadgeVersion] }
        struct HelixResponse: Decodable { let data: [BadgeSet] }

        var mergedBadges: [String: [String: String]] = [:]

        // Параллельная загрузка глобальных и канальных бейджей
        async let globalTask: [BadgeSet] = {
            do {
                let url = URL(string: "https://api.twitch.tv/helix/chat/badges/global")!
                var req = URLRequest(url: url)
                req.addValue("Bearer \(TWITCH_HELIX_BEARER_TOKEN)", forHTTPHeaderField: "Authorization")
                req.addValue(TWITCH_HELIX_CLIENT_ID, forHTTPHeaderField: "Client-Id")
                let (data, _) = try await URLSession.shared.data(for: req)
                return (try JSONDecoder().decode(HelixResponse.self, from: data)).data
            } catch {
                print("Ошибка загрузки глобальных бейджей: \(error)")
                return []
            }
        }()

        async let channelTask: [BadgeSet] = {
            do {
                let userId = try await TwitchChatManager.sharedChannelId(login: channelLogin)
                let url = URL(string: "https://api.twitch.tv/helix/chat/badges?broadcaster_id=\(userId)")!
                var req = URLRequest(url: url)
                req.addValue("Bearer \(TWITCH_HELIX_BEARER_TOKEN)", forHTTPHeaderField: "Authorization")
                req.addValue(TWITCH_HELIX_CLIENT_ID, forHTTPHeaderField: "Client-Id")
                let (data, _) = try await URLSession.shared.data(for: req)
                return (try JSONDecoder().decode(HelixResponse.self, from: data)).data
            } catch {
                print("Ошибка загрузки канальных бейджей: \(error)")
                return []
            }
        }()

        let (globalSets, channelSets) = await (globalTask, channelTask)

        for set in globalSets + channelSets {
            var ver: [String: String] = mergedBadges[set.set_id] ?? [:]
            for v in set.versions {
                if let url = v.image_url_2x, !url.isEmpty { ver[v.id] = url }
            }
            if !ver.isEmpty { mergedBadges[set.set_id] = ver }
        }

        DispatchQueue.main.async { self.allBadgeImages = mergedBadges }
    }

    // MARK: - Загрузка эмоутов (параллельно)
    func loadGlobalEmotes() async {
        // Все источники загружаем параллельно
        async let stv: Void = load7TVEmotes()
        async let stvChannel: Void = load7TVChannelEmotes(channelLogin: TWITCH_CHANNEL)
        async let bttvGlobal: Void = loadBTTVGlobalEmotes()
        async let bttvChannel: Void = loadBTTVChannelEmotes(channelLogin: TWITCH_CHANNEL)
        async let twitchGlobal: Void = loadTwitchGlobalEmotes()
        _ = await (stv, stvChannel, bttvGlobal, bttvChannel, twitchGlobal)
    }

    private func loadTwitchGlobalEmotes() async {
        let url = URL(string: "https://api.twitch.tv/helix/chat/emotes/global")!
        var req = URLRequest(url: url)
        addHelixHeaders(&req)
        struct Response: Decodable { let data: [Emote] }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let result = try JSONDecoder().decode(Response.self, from: data)
            var map: [String: String] = [:]
            for emote in result.data {
                var url = emote.images.url_1x
                if let format = emote.format, format.contains("animated") {
                    url = url.replacingOccurrences(of: "/static/", with: "/animated/")
                }
                map[emote.name] = url
            }
            DispatchQueue.main.async { self.emoteMap = map }
        } catch {
            print("Ошибка загрузки смайликов Twitch: \(error)")
        }
    }

    func load7TVEmotes() async {
        let url = URL(string: "https://7tv.io/v3/emote-sets/global")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct GlobalEmoteResponse: Decodable { let emotes: [STVEmote] }
            let decoded = try JSONDecoder().decode(GlobalEmoteResponse.self, from: data)
            var map: [String: String] = [:]
            for emote in decoded.emotes {
                if let url = emote.url(size: "1x", format: "WEBP") { map[emote.name] = url }
            }
            DispatchQueue.main.async { self.stvEmoteMap = map }
        } catch {}
    }

    func load7TVChannelEmotes(channelLogin: String) async {
        let userUrl = URL(string: "https://api.ivr.fi/v2/twitch/user?login=\(channelLogin)")!
        do {
            let (userData, _) = try await URLSession.shared.data(from: userUrl)
            struct User: Decodable { let id: String }
            let userObj = try JSONDecoder().decode([User].self, from: userData)
            guard let userId = userObj.first?.id else { return }

            let setUrl = URL(string: "https://7tv.io/v3/users/twitch/\(userId)")!
            let (data, _) = try await URLSession.shared.data(from: setUrl)

            struct UserSet: Decodable {
                struct EmoteSet: Decodable {
                    struct Emote: Decodable {
                        let name: String
                        let data: DataField
                        struct DataField: Decodable {
                            let animated: Bool?
                            let host: HostField
                            struct HostField: Decodable {
                                let url: String
                                let files: [FileField]
                                struct FileField: Decodable { let name: String; let format: String }
                            }
                        }
                    }
                    let emotes: [Emote]
                }
                let emote_set: EmoteSet?
            }

            let userSet = try JSONDecoder().decode(UserSet.self, from: data)
            var map: [String: (url: String, animated: Bool)] = [:]
            if let emotes = userSet.emote_set?.emotes {
                for emote in emotes {
                    if let firstFile = emote.data.host.files.first {
                        let baseUrl = emote.data.host.url.hasPrefix("http") ? emote.data.host.url : "https:" + emote.data.host.url
                        map[emote.name] = (url: "\(baseUrl)/\(firstFile.name)", animated: emote.data.animated ?? false)
                    }
                }
            }
            DispatchQueue.main.async { self.stvChannelEmoteMap = map }
        } catch { print("Ошибка загрузки 7TV channel emotes: \(error)") }
    }

    func loadBTTVGlobalEmotes() async {
        let url = URL(string: "https://api.betterttv.net/3/cached/emotes/global")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Emote: Decodable { let code: String; let id: String }
            let emotes = try JSONDecoder().decode([Emote].self, from: data)
            var map: [String: String] = [:]
            for emote in emotes { map[emote.code] = "https://cdn.betterttv.net/emote/\(emote.id)/1x" }
            DispatchQueue.main.async { self.bttvGlobalMap = map }
        } catch { print("BTTV global load error: \(error)") }
    }

    func loadBTTVChannelEmotes(channelLogin: String) async {
        let userUrl = URL(string: "https://api.ivr.fi/v2/twitch/user?login=\(channelLogin)")!
        do {
            let (userData, _) = try await URLSession.shared.data(from: userUrl)
            struct User: Decodable { let id: String }
            let userObj = try JSONDecoder().decode([User].self, from: userData)
            guard let userId = userObj.first?.id else { return }

            let url = URL(string: "https://api.betterttv.net/3/cached/users/twitch/\(userId)")!
            let (data, _) = try await URLSession.shared.data(from: url)

            struct BTTVUserEmotesResponse: Decodable {
                let channelEmotes: [Emote]
                let sharedEmotes: [Emote]
                struct Emote: Decodable { let code: String; let id: String }
            }
            let decoded = try JSONDecoder().decode(BTTVUserEmotesResponse.self, from: data)
            var map: [String: String] = [:]
            for emote in decoded.channelEmotes + decoded.sharedEmotes {
                map[emote.code] = "https://cdn.betterttv.net/emote/\(emote.id)/1x"
            }
            DispatchQueue.main.async { self.bttvChannelMap = map }
        } catch {}
    }

    // MARK: - Парсинг сообщения с эмоутами
    func parseMessageWithEmotes(_ text: String) -> [MessagePart] {
        let words = text.split(separator: " ")
        var result: [MessagePart] = []
        var textBuffer: [String] = []

        for word in words {
            let stringWord = String(word)
            if let emote = getEmote(for: stringWord) {
                flushTextBuffer(&textBuffer, to: &result)
                result.append(emote)
            } else {
                textBuffer.append(stringWord)
            }
        }

        flushTextBuffer(&textBuffer, to: &result)
        return result
    }

    private func getEmote(for word: String) -> MessagePart? {
        if let url = emoteMap[word] { return .emote(name: word, url: url, animated: false) }
        if let entry = stvChannelEmoteMap[word] { return .emote(name: word, url: entry.url, animated: entry.animated) }
        if let url = stvEmoteMap[word] { return .emote(name: word, url: url, animated: false) }
        if let url = bttvChannelMap[word] { return .emote(name: word, url: url, animated: false) }
        if let url = bttvGlobalMap[word] { return .emote(name: word, url: url, animated: false) }
        return nil
    }

    private func flushTextBuffer(_ buffer: inout [String], to result: inout [MessagePart]) {
        guard !buffer.isEmpty else { return }
        result.append(.text(buffer.joined(separator: " ")))
        buffer.removeAll()
    }

    // MARK: - Цвет из HEX
    private func colorFromHex(_ hex: String) -> Color {
        let hexSanitized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        if hexSanitized.count == 3 {
            let r = String(repeating: hexSanitized[hexSanitized.startIndex], count: 2)
            let g = String(repeating: hexSanitized[hexSanitized.index(hexSanitized.startIndex, offsetBy: 1)], count: 2)
            let b = String(repeating: hexSanitized[hexSanitized.index(hexSanitized.startIndex, offsetBy: 2)], count: 2)
            guard let int = UInt64(r + g + b, radix: 16) else { return .primary }
            return Color(red: Double((int >> 16) & 0xFF) / 255,
                         green: Double((int >> 8) & 0xFF) / 255,
                         blue: Double(int & 0xFF) / 255)
        }
        guard hexSanitized.count == 6, let int = UInt64(hexSanitized, radix: 16) else { return .primary }
        return Color(red: Double((int >> 16) & 0xFF) / 255,
                     green: Double((int >> 8) & 0xFF) / 255,
                     blue: Double(int & 0xFF) / 255)
    }

    // MARK: - EventSub подписка
    private func subscribeToEventSub(sessionId: String) async {
        var targetUserId = self.channelId ?? ""
        if targetUserId.isEmpty {
            targetUserId = (try? await TwitchChatManager.sharedChannelId(login: TWITCH_CHANNEL)) ?? ""
        }
        guard !targetUserId.isEmpty else {
            print("[EventSub] Не удалось определить user_id для подписки")
            return
        }

        let desiredTypes = [
            "channel.channel_points_custom_reward_redemption.add",
            "channel.chat.message"
        ]

        // Получаем активные подписки
        var activeTypes = Set<String>()
        do {
            let getURL = URL(string: "https://api.twitch.tv/helix/eventsub/subscriptions?status=enabled")!
            var getReq = URLRequest(url: getURL)
            getReq.httpMethod = "GET"
            addHelixHeaders(&getReq)
            let (getData, _) = try await URLSession.shared.data(for: getReq)
            struct GetRoot: Decodable { struct Item: Decodable { let type: String? }; let data: [Item]? }
            if let decoded = try? JSONDecoder().decode(GetRoot.self, from: getData) {
                decoded.data?.compactMap { $0.type }.forEach { activeTypes.insert($0) }
            }
        } catch {
            print("[EventSub] GET subscriptions error: \(error)")
        }

        // Подписываемся на недостающие типы
        for t in desiredTypes where !activeTypes.contains(t) {
            do {
                let url = URL(string: "https://api.twitch.tv/helix/eventsub/subscriptions")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                addHelixHeaders(&req)
                req.addValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try buildEventSubSubscriptionBody(sessionId: sessionId, userId: targetUserId, overrideType: t)
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse {
                    print("[EventSub] subscribe status for type=\(t): \(http.statusCode)")
                }
            } catch {
                print("[EventSub] subscribe error for type=\(t): \(error)")
            }
        }
    }
}

// MARK: - EventSub WebSocket
extension TwitchChatManager {

    private func findStringValue(forKey targetKey: String, in json: Any) -> String? {
        if let dict = json as? [String: Any] {
            for (key, value) in dict {
                if key == targetKey {
                    if let str = value as? String { return str }
                    if let num = value as? NSNumber { return num.stringValue }
                }
                if let found = findStringValue(forKey: targetKey, in: value) { return found }
            }
        } else if let array = json as? [Any] {
            for item in array {
                if let found = findStringValue(forKey: targetKey, in: item) { return found }
            }
        }
        return nil
    }

    // MARK: - Запуск WebSocket
    func startEventSubWebSocket() {
        // Отменяем отложенное переподключение, если оно есть
        reconnectTask?.cancel()
        reconnectTask = nil

        // Не дублируем активное соединение
        if let task = eventSubWebSocketTask {
            switch task.state {
            case .running, .suspended: return
            default: break
            }
        }

        print("[EventSub] Подключаемся (попытка \(reconnectAttempt + 1))…")
        DispatchQueue.main.async { self.isConnected = "Подключение…" }

        let task = urlSession.webSocketTask(with: eventSubURL)
        eventSubWebSocketTask = task
        task.resume()
        resetKeepaliveTimer()
        listenEventSubMessages()
    }

    // MARK: - Keepalive таймер
    /// Сбрасывает таймер. Если за константу Constants.keepaliveTimeout + 5с не придёт ни одного сообщения — переподключаемся.
    private func resetKeepaliveTimer() {
        cancelKeepaliveTimer()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.keepaliveTimer = Timer.scheduledTimer(
                withTimeInterval: Constants.keepaliveTimeout + 5,
                repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }
                print("[EventSub] Keepalive timeout — переподключаемся")
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

    // MARK: - Чтение сообщений
    private func listenEventSubMessages() {
        eventSubWebSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                print("[EventSub] receive error: \(error)")
                DispatchQueue.main.async { self.isConnected = "Ошибка соединения" }
                self.scheduleReconnect()

            case .success(let message):
                // Любое входящее сообщение сбрасывает таймер keepalive
                self.resetKeepaliveTimer()
                DispatchQueue.main.async { self.isConnected = "Подключено" }

                switch message {
                case .string(let text):
                    self.handleEventSubJSONString(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleEventSubJSONString(text)
                    }
                @unknown default:
                    break
                }
                // Продолжаем слушать только если соединение активно
                if let task = self.eventSubWebSocketTask, task.state == .running {
                    self.listenEventSubMessages()
                }
            }
        }
    }

    // MARK: - Обработка JSON сообщений EventSub
    private func handleEventSubJSONString(_ text: String) {
        print("[EventSub] <- \(text.prefix(200))")

        struct Envelope: Decodable {
            struct Metadata: Decodable { let message_type: String; let subscription_type: String? }
            struct Payload: Decodable {
                struct Session: Decodable { let id: String?; let reconnect_url: String? }
                let session: Session?
            }
            let metadata: Metadata
            let payload: Payload?
        }

        guard let data = text.data(using: .utf8),
              let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return }

        let type = env.metadata.message_type
        let subType = env.metadata.subscription_type

        switch type {
        case "session_welcome":
            if let id = env.payload?.session?.id {
                eventSubSessionId = id
                reconnectAttempt = 0  // Успешное подключение — сбрасываем счётчик
                print("[EventSub] session_welcome. session_id=\(id)")
                Task { await self.subscribeToEventSub(sessionId: id) }
            }

        case "session_reconnect":
            // Twitch просит переподключиться к новому URL
            print("[EventSub] session_reconnect — переподключаемся")
            DispatchQueue.main.async { self.isConnected = "Переподключение…" }
            scheduleReconnect(immediately: true)

        case "session_keepalive":
            print("[EventSub] keepalive")
            // Таймер уже сброшен выше в listenEventSubMessages

        case "notification":
            handleNotification(subType: subType, text: text)

        default:
            break
        }
    }

    private func handleNotification(subType: String?, text: String) {
        let jsonAny: Any? = text.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }

        if subType == "channel.channel_points_custom_reward_redemption.add" {
            let messageIdStr = jsonAny.flatMap { findStringValue(forKey: "message_id", in: $0) }
            let userNameStr = jsonAny.flatMap { findStringValue(forKey: "user_name", in: $0) }
            let titleStr = jsonAny.flatMap { findStringValue(forKey: "title", in: $0) }

            let computedId = messageIdStr.flatMap { UUID(uuidString: $0) } ?? UUID()
            let sender = userNameStr ?? "eventsub"
            let baseText = titleStr.flatMap { $0.isEmpty ? nil : $0 } ?? String(text.prefix(120))
            let messageText = "Получена награда — \(baseText)"
            let badgeData = badgeViews(from: [], badgeUrlMap: allBadgeImages)

            let notif = Notification(id: computedId, sender: sender, text: messageText,
                                     badges: [], senderColor: .gray, badgeViewData: badgeData)
            let msg = Message(id: UUID(), sender: sender, text: messageText,
                              badges: [], senderColor: .gray, badgeViewData: badgeData)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.notifications.append(notif)
                self.messages.append(msg)
                if self.messages.count > Constants.maxMessages {
                    self.messages.removeFirst(self.messages.count - Constants.maxMessages)
                }
            }

        } else if subType == "channel.chat.message" {
            guard let jsonDict = jsonAny as? [String: Any],
                  let payload = jsonDict["payload"] as? [String: Any],
                  let event = payload["event"] as? [String: Any],
                  let senderShown = event["chatter_user_name"] as? String,
                  let messageDict = event["message"] as? [String: Any],
                  let msgText = messageDict["text"] as? String else {
                print("[EventSub] Не удалось извлечь данные chat.message")
                return
            }

            let senderColorHex = event["color"] as? String
            let color: Color? = (senderColorHex?.isEmpty == false) ? colorFromHex(senderColorHex!) : nil
            let badges = event["badges"] as? [[String: Any]] ?? []
            let badgePairs: [(String, String)] = badges.compactMap { dict in
                guard let set = dict["set_id"] as? String, let version = dict["id"] as? String else { return nil }
                return (set, version)
            }

            let badgeViewData = badgeViews(from: badgePairs, badgeUrlMap: allBadgeImages)
            setLastMessageThrottled(Message(sender: senderShown, text: msgText,
                                            badges: badgePairs, senderColor: color, badgeViewData: badgeViewData))
        }
    }

    // MARK: - Переподключение с exponential backoff
    /// Планирует переподключение с нарастающей задержкой.
    private func scheduleReconnect(immediately: Bool = false) {
        cancelKeepaliveTimer()
        eventSubWebSocketTask?.cancel(with: .goingAway, reason: nil)
        eventSubWebSocketTask = nil

        reconnectTask?.cancel()

        let delay: TimeInterval
        if immediately {
            delay = 0
        } else {
            // Exponential backoff: 1, 2, 4, 8, 16, 32, 60 секунд
            delay = min(pow(2.0, Double(reconnectAttempt)), Constants.maxReconnectDelay)
            reconnectAttempt += 1
            print("[EventSub] Следующая попытка через \(Int(delay))с (попытка \(reconnectAttempt))")
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if delay > 0 { self.isConnected = "Переподключение через \(Int(delay))с…" }
        }

        reconnectTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self?.startEventSubWebSocket()
        }
    }

    private func sendEventSubPong() {
        eventSubWebSocketTask?.sendPing { error in
            if let error { print("[EventSub] ping/pong send error: \(error)") }
        }
    }

    private func reconnectEventSub() {
        scheduleReconnect()
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

// MARK: - Stream Info
extension TwitchChatManager {
    private struct ChannelsResponse: Decodable {
        struct Channel: Decodable {
            let broadcaster_id: String
            let title: String
            let game_id: String
            let game_name: String
        }
        let data: [Channel]
    }

    private struct GamesResponse: Decodable {
        struct Game: Decodable { let id: String; let name: String; let box_art_url: String }
        let data: [Game]
    }

    fileprivate func runStreamInfoLoop() async {
        if channelId == nil {
            if let id = try? await TwitchChatManager.sharedChannelId(login: TWITCH_CHANNEL) {
                self.channelId = id
            } else {
                print("[TwitchChat] fetchChannelId failed")
            }
        }
        while !Task.isCancelled {
            await refreshStreamInfo()
            try? await Task.sleep(nanoseconds: Constants.streamInfoInterval)
        }
    }

    @MainActor
    private func applyChannel(title: String, gameName: String) {
        if streamTitle != title { streamTitle = title }
        if categoryName != gameName { categoryName = gameName }
    }

    @MainActor
    private func applyGameImage(url: URL?) {
        if categoryImageURL != url { categoryImageURL = url }
    }

    private func refreshStreamInfo() async {
        do {
            if channelId == nil {
                channelId = try await TwitchChatManager.sharedChannelId(login: TWITCH_CHANNEL)
            }
            guard let id = channelId else { return }

            let chURL = URL(string: "https://api.twitch.tv/helix/channels?broadcaster_id=\(id)")!
            var chReq = URLRequest(url: chURL)
            addHelixHeaders(&chReq)
            let (chData, _) = try await URLSession.shared.data(for: chReq)
            let channel = try JSONDecoder().decode(ChannelsResponse.self, from: chData).data.first
            guard let channel else { return }

            await applyChannel(title: channel.title, gameName: channel.game_name)

            if !channel.game_id.isEmpty {
                let gURL = URL(string: "https://api.twitch.tv/helix/games?id=\(channel.game_id)")!
                var gReq = URLRequest(url: gURL)
                addHelixHeaders(&gReq)
                let (gData, _) = try await URLSession.shared.data(for: gReq)
                let boxTemplate = (try JSONDecoder().decode(GamesResponse.self, from: gData)).data.first?.box_art_url ?? ""
                let finalURL = URL(string: boxTemplate
                    .replacingOccurrences(of: "{width}", with: "300")
                    .replacingOccurrences(of: "{height}", with: "450"))
                await applyGameImage(url: finalURL)
            } else {
                await applyGameImage(url: nil)
            }
        } catch {
            print("Ошибка обновления информации о стриме: \(error)")
        }
    }
}

// MARK: - Convenience inits
extension TwitchChatManager.Message {
    init(sender: String, text: String, badges: [(String, String)], senderColor: Color?, badgeViewData: [BadgeViewData]) {
        self.id = UUID()
        self.sender = sender
        self.text = text
        self.badges = badges
        self.senderColor = senderColor
        self.badgeViewData = badgeViewData
    }
}

extension TwitchChatManager.Notification {
    init(sender: String, text: String, badges: [(String, String)], senderColor: Color?, badgeViewData: [BadgeViewData]) {
        self.id = UUID()
        self.sender = sender
        self.text = text
        self.badges = badges
        self.senderColor = senderColor
        self.badgeViewData = badgeViewData
    }
}

// MARK: - DisplayMessage
struct DisplayMessage: Identifiable {
    let id = UUID()
    let badges: [BadgeViewData]
    let sender: String
    let senderColor: Color
    let visibleParts: [MessagePart]
    let isTruncated: Bool
}
