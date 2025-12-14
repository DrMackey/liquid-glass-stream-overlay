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
    // Для совместимости оставляем функцию, но используем кэш менеджера
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

// Канал Twitch, к которому подключаемся по IRC
let TWITCH_CHANNEL = Config.shared.TwitchChannel
let TWITCH_HELIX_CLIENT_ID = Config.shared.TwitchHelixClientID
let TWITCH_HELIX_BEARER_TOKEN = Config.shared.TwitchHelixBearerToken

// MARK: - Модель частей сообщения (текст/эмоут)
/// Представляет часть сообщения: текст или эмот.
enum MessagePart: Hashable {
    case text(String) // Обычный текст
    case emote(name: String, url: String, animated: Bool) // Эмоут с URL и признаком анимации
}

// MARK: - Отображение эмоутов (анимированные и статичные)
// Реализация EmoteImageView для отображения gif-по-URL или AsyncImage для обычных картинок
struct EmoteImageView: View {
    let url: URL
    let size: CGFloat
    let animated: Bool // Добавлен параметр animated для определения анимации
    
    var body: some View {
        // Выбираем AnimatedImage для gif/webp или AsyncImage для статичных
        Group {
            let ext = url.pathExtension.lowercased()
            if animated || ext == "webp" || ext == "gif" {
                AnimatedImage(url: url)
                    .onFailure { error in
                        print("ОООШИБКА \(error)")
                    }
                    .resizable()
                    .indicator(.activity)
                    .transition(.fade)
                    .scaledToFit()
                    .frame(height: size)
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
//                        Text("?")
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
        if let image = NSImage(data: data) {
            imageView.image = image
        }
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

// Данные для визуализации бейджиков в интерфейсе
struct BadgeViewData: Identifiable, Hashable, Equatable {
    let id = UUID()
    let set: String
    let version: String
    let url: URL?
}

// MARK: - Основной менеджер чата Twitch (IRC + Helix + эмоута)
final class TwitchChatManager: ObservableObject {
    // Кэш channelId для всех обращений, чтобы запрашивать его только один раз
    private static var cachedChannelId: String? = nil
    private static var channelIdTask: Task<String, Error>? = nil

    // Combine cancellables for reactive subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Единая точка получения channelId с кэшем и дедупликацией запросов
    static func sharedChannelId(login: String) async throws -> String {
        if let id = cachedChannelId { return id }
        if let task = channelIdTask { return try await task.value }
        let task = Task<String, Error> {
            // ВАЖНО: Twitch логины — в нижнем регистре
            let url = URL(string: "https://api.twitch.tv/helix/users?login=\(login.lowercased())")!
            var req = URLRequest(url: url)
            req.addValue("Bearer \(TWITCH_HELIX_BEARER_TOKEN)", forHTTPHeaderField: "Authorization")
            req.addValue(TWITCH_HELIX_CLIENT_ID, forHTTPHeaderField: "Client-Id")
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                print("[TwitchChat] helix/users status: \(http.statusCode)")
            }
            struct UsersResponse: Decodable { struct User: Decodable { let id: String }; let data: [User] }
            let decoded = try JSONDecoder().decode(UsersResponse.self, from: data)
            guard let id = decoded.data.first?.id else {
                throw URLError(.badServerResponse)
            }
            return id
        }
        channelIdTask = task
        do {
            let id = try await task.value
            cachedChannelId = id
            channelIdTask = nil
            return id
        } catch {
            channelIdTask = nil
            throw error
        }
    }

    // Внутренняя модель информации о бейдже
    struct BadgeInfo: Hashable {
        let set: String
        let version: String
        let imageUrl: String
    }

    // Внутренняя модель сообщения чата
    struct Message: Equatable, Identifiable {
        let id: UUID
        let sender: String
        let text: String
        let badges: [(String, String)]
        let senderColor: Color?
        let badgeViewData: [BadgeViewData]
        
        // Сравнение сообщений по всем полям для корректной дифференциации
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

    // Паблишед-состояния для UI: последнее сообщение, история, карты эмоутов и бейджей
    @Published var lastMessage: Message?
    @Published var messages: [Message] = []
    @Published var notifications: [Notification] = []

    @Published var allBadgeImages: [String: [String: String]] = [:]
    @Published var emoteMap: [String: String] = [:]
    @Published var stvEmoteMap: [String: String] = [:]
    @Published var stvChannelEmoteMap: [String: (url: String, animated: Bool)] = [:]
    @Published var bttvGlobalMap: [String: String] = [:]
    @Published var bttvChannelMap: [String: String] = [:]
    
    // Паблишед-поля для GlassBarContainer: заголовок/категория/обложка
    @Published var streamTitle: String = ""
    @Published var categoryName: String = ""
    @Published var categoryImageURL: URL? = nil

    // Транспорт IRC, учётные данные и вспомогательные таймеры/очереди
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "TwitchChatQueue")
    private let oauthToken = "oauth:2s4x0c089w8u5ouwdoi5veduxk9sbr"
    private let nick = "DrMackey_"
    private(set) var channelId: String? = nil
    private var lastDisplayTime: Date = .distantPast
    private var pendingMessage: Message? = nil
    private var displayTimer: Timer?
    
    // Task для обновления информации о стриме
    private var streamInfoTask: Task<Void, Never>?

    // MARK: - EventSub (WebSocket)
    private var eventSubWebSocketTask: URLSessionWebSocketTask?
    private var eventSubSessionId: String?
    private let eventSubURL = URL(string: "wss://eventsub.wss.twitch.tv/ws")!
    private let urlSession = URLSession(configuration: .default)

    // Инициализация: запуск фонового цикла обновления информации о стриме
    init() {
//        print("[TwitchChat] init()")
        // Стартуем фоновое обновление информации о стриме/категории
        streamInfoTask = Task { [weak self] in
            await self?.runStreamInfoLoop()
        }
        // Запускаем EventSub WebSocket при старте приложения
        startEventSubWebSocket()
        // Подписка на авто-очистку уведомлений
        setupNotificationsAutoClear()
    }

    /// Подписывается на изменения массива notifications и для каждого нового уведомления
    /// запускает таймер на 5 секунд, по истечении которого это уведомление удаляется из массива.
    private func setupNotificationsAutoClear() {
        // Храним локальную копию последнего известного состояния, чтобы находить добавленные элементы
        var lastKnown: [Notification] = self.notifications
        
        $notifications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] current in
                guard let self = self else { return }
                // Найдём новые элементы, которых не было в lastKnown (по id)
                let lastIds = Set(lastKnown.map { $0.id })
                let newOnes = current.filter { !lastIds.contains($0.id) }
                
                for notif in newOnes {
                    // Запускаем отложенное удаление конкретного уведомления
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                        guard let self = self else { return }
                        // Удаляем уведомление по id, если оно всё ещё есть в массиве
                        self.notifications.removeAll { $0.id == notif.id }
                    }
                }
                // Обновим lastKnown после обработки
                lastKnown = current
            }
            .store(in: &cancellables)
    }

    // Добавляет обязательные заголовки Helix к запросу
    // Единое добавление Helix-заголовков (по примеру curl)
    private func addHelixHeaders(_ request: inout URLRequest) {
        // Здесь подставляется Client-Id из TWITCH_HELIX_CLIENT_ID и Bearer-токен
        request.addValue("Bearer \(TWITCH_HELIX_BEARER_TOKEN)", forHTTPHeaderField: "Authorization")
        request.addValue(TWITCH_HELIX_CLIENT_ID, forHTTPHeaderField: "Client-Id")
    }

    // Преобразует пары (set, version) в массив данных для отображения бейджей
    func badgeViews(from badges: [(String, String)], badgeUrlMap: [String: [String: String]]) -> [BadgeViewData] {
        badges.map { (set, version) -> BadgeViewData in
            let url = badgeUrlMap[set]?[version].flatMap { URL(string: $0) }
            return BadgeViewData(set: set, version: version, url: url)
        }
    }

    // Троттлинг вывода сообщений (не чаще 1/с), буферизация и таймер
    private func setLastMessageThrottled(_ message: Message) {
        let now = Date()
        let interval = now.timeIntervalSince(lastDisplayTime)
        if interval >= 1.0 {
            lastDisplayTime = now
            DispatchQueue.main.async { [weak self] in
                self?.lastMessage = message
                if let self = self {
                    self.messages.append(message)
                    if self.messages.count > 20 { self.messages.removeFirst(self.messages.count - 20) }
                }
            }
        } else {
            pendingMessage = message
            displayTimer?.invalidate()
            let delay = 1.0 - interval
            displayTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self = self, let pending = self.pendingMessage else { return }
                self.lastDisplayTime = Date()
                DispatchQueue.main.async {
                    self.lastMessage = pending
                    self.messages.append(pending)
                    if self.messages.count > 20 { self.messages.removeFirst(self.messages.count - 20) }
                }
                self.pendingMessage = nil
                self.displayTimer = nil
            }
        }
    }

    // Остановка IRC и фоновых задач, очистка временных состояний
    func stop() {
        print("[TwitchChat] stop() — останавливаем IRC и фоновые задачи")
        // Останавливаем EventSub WebSocket
        eventSubWebSocketTask?.cancel(with: .goingAway, reason: nil)
        eventSubWebSocketTask = nil
        // Останавливаем фоновые обновления информации о стриме
        streamInfoTask?.cancel()
        streamInfoTask = nil // чтобы в start() можно было создать новую задачу
    }

    // Загрузка глобальных и канальных бейджей через Helix
    func loadAllBadges(channelLogin: String) async {
        var mergedBadges: [String: [String: String]] = [:]
        do {
            // Глобальные бейджи
            let urlGlobal = URL(string: "https://api.twitch.tv/helix/chat/badges/global")!
            var reqGlobal = URLRequest(url: urlGlobal)
            addHelixHeaders(&reqGlobal)
            let (dataGlobal, resp) = try await URLSession.shared.data(for: reqGlobal)
//            if let http = resp as? HTTPURLResponse {
//                print("[TwitchChat] badges/global status: \(http.statusCode)")
//            }
            struct BadgeVersion: Decodable { let id: String; let image_url_1x: String? }
            struct BadgeSet: Decodable { let set_id: String; let versions: [BadgeVersion] }
            struct HelixResponse: Decodable { let data: [BadgeSet] }
            let global = try JSONDecoder().decode(HelixResponse.self, from: dataGlobal)
            for set in global.data {
                var ver: [String: String] = [:]
                for v in set.versions { if let url = v.image_url_1x, !url.isEmpty { ver[v.id] = url } }
                if !ver.isEmpty { mergedBadges[set.set_id] = ver }
            }
        } catch { print("Ошибка загрузки глобальных баджей: \(error)") }
        do {
            // Канальные бейджи
            let userURL = URL(string: "https://api.twitch.tv/helix/users?login=\(channelLogin)")!
            var userRequest = URLRequest(url: userURL)
            addHelixHeaders(&userRequest)
            let (userData, resp) = try await URLSession.shared.data(for: userRequest)
//            if let http = resp as? HTTPURLResponse {
//                print("[TwitchChat] users?login= status: \(http.statusCode)")
//            }
            struct UserResponse: Decodable { struct User: Decodable { let id: String }; let data: [User] }
            let decodedUser = try JSONDecoder().decode(UserResponse.self, from: userData)
            guard let userId = decodedUser.data.first?.id else { return }
            let badgeURL = URL(string: "https://api.twitch.tv/helix/chat/badges?broadcaster_id=\(userId)")!
            var badgeRequest = URLRequest(url: badgeURL)
            addHelixHeaders(&badgeRequest)
            let (badgeData, resp2) = try await URLSession.shared.data(for: badgeRequest)
//            if let http = resp2 as? HTTPURLResponse {
//                print("[TwitchChat] chat/badges?broadcaster_id= status: \(http.statusCode)")
//            }
            struct BadgeVersion: Decodable { let id: String; let image_url_1x: String? }
            struct BadgeSet: Decodable { let set_id: String; let versions: [BadgeVersion] }
            struct HelixResponse: Decodable { let data: [BadgeSet] }
            let channel = try JSONDecoder().decode(HelixResponse.self, from: badgeData)
            for set in channel.data {
                var ver: [String: String] = mergedBadges[set.set_id] ?? [:]
                for v in set.versions { if let url = v.image_url_1x, !url.isEmpty { ver[v.id] = url } }
                if !ver.isEmpty { mergedBadges[set.set_id] = ver }
            }
        } catch { print("Ошибка загрузки каналовых баджей: \(error)") }
        DispatchQueue.main.async { self.allBadgeImages = mergedBadges }
    }

    // Загрузка глобальных эмоутов 7TV
    func load7TVEmotes() async {
        let url = URL(string: "https://7tv.io/v3/emote-sets/global")!
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
//            if let http = resp as? HTTPURLResponse {
//                print("[TwitchChat] 7TV global status: \(http.statusCode)")
//            }
            struct GlobalEmoteResponse: Decodable { let emotes: [STVEmote] }
            let decoded = try JSONDecoder().decode(GlobalEmoteResponse.self, from: data)
            var map: [String: String] = [:]
            for emote in decoded.emotes {
                if let url = emote.url(size: "1x", format: "WEBP") {
                    map[emote.name] = url
                }
            }
            DispatchQueue.main.async {
                self.stvEmoteMap = map
            }
        } catch {
//            print("Ошибка загрузки 7tv смайликов: \(error)")
        }
    }

    // Загрузка каналовых эмоутов 7TV (через IVR -> 7tv user set)
    func load7TVChannelEmotes(channelLogin: String) async {
        let userUrl = URL(string: "https://api.ivr.fi/v2/twitch/user?login=\(channelLogin)")!
        do {
            let (userData, userHTTPResp) = try await URLSession.shared.data(from: userUrl)
//            if let http = userHTTPResp as? HTTPURLResponse {
//                print("[TwitchChat] IVR user status: \(http.statusCode)")
//            }
            struct User: Decodable { let id: String }
            let userObj = try JSONDecoder().decode([User].self, from: userData)
            guard let userId = userObj.first?.id else { return }
            let setUrl = URL(string: "https://7tv.io/v3/users/twitch/\(userId)")!
            let (data, resp2) = try await URLSession.shared.data(from: setUrl)
//            if let http = resp2 as? HTTPURLResponse {
//                print("[TwitchChat] 7TV user set status: \(http.statusCode)")
//            }
            struct UserSet: Decodable {
                struct EmoteSet: Decodable {
                    struct Emote: Decodable {
                        let id: String
                        let name: String
                        let data: DataField
                        struct DataField: Decodable {
                            let id: String
                            let name: String
                            let animated: Bool?
                            let host: HostField
                            struct HostField: Decodable {
                                let url: String
                                let files: [FileField]
                                struct FileField: Decodable {
                                    let name: String
                                    let format: String
                                    let width: Int?
                                    let height: Int?
                                }
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
                        let urlString = "\(baseUrl)/\(firstFile.name)"
                        let isAnimated = emote.data.animated ?? false
                        map[emote.name] = (url: urlString, animated: isAnimated)
                    }
                }
            }
            DispatchQueue.main.async { self.stvChannelEmoteMap = map }
        } catch { print("Ошибка загрузки 7tv channel emotes: \(error)") }
    }

    // Загрузка глобальных эмоутов BTTV
    func loadBTTVGlobalEmotes() async {
        let url = URL(string: "https://api.betterttv.net/3/cached/emotes/global")!
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
//            if let http = resp as? HTTPURLResponse {
//                print("[TwitchChat] BTTV global status: \(http.statusCode)")
//            }
            struct Emote: Decodable { let code: String; let id: String }
            let emotes = try JSONDecoder().decode([Emote].self, from: data)
            var map: [String: String] = [:]
            for emote in emotes { map[emote.code] = "https://cdn.betterttv.net/emote/\(emote.id)/1x" }
            DispatchQueue.main.async { self.bttvGlobalMap = map }
        } catch { print("BTTV global load error: \(error)") }
    }

    // Загрузка каналовых эмоутов BTTV
    func loadBTTVChannelEmotes(channelLogin: String) async {
        let userUrl = URL(string: "https://api.ivr.fi/v2/twitch/user?login=\(channelLogin)")!
        do {
            let (userData, userHTTPResp) = try await URLSession.shared.data(from: userUrl)
//            if let http = userHTTPResp as? HTTPURLResponse {
//                print("[TwitchChat] IVR user (BTTV) status: \(http.statusCode)")
//            }
            struct User: Decodable { let id: String }
            let userObj = try JSONDecoder().decode([User].self, from: userData)
            guard let userId = userObj.first?.id else { return }
            let url = URL(string: "https://api.betterttv.net/3/cached/users/twitch/\(userId)")!
            let (data, bttvHTTPResp) = try await URLSession.shared.data(from: url)
//            if let http = bttvHTTPResp as? HTTPURLResponse {
//                print("[TwitchChat] BTTV user status: \(http.statusCode)")
//            }
            struct BTTVUserEmotesResponse: Decodable {
                let channelEmotes: [Emote]
                let sharedEmotes: [Emote]
                struct Emote: Decodable { let code: String; let id: String }
            }
            let decodedBTTV = try JSONDecoder().decode(BTTVUserEmotesResponse.self, from: data)
            var map: [String: String] = [:]
            for emote in decodedBTTV.channelEmotes + decodedBTTV.sharedEmotes {
                map[emote.code] = "https://cdn.betterttv.net/emote/\(emote.id)/1x"
            }
            DispatchQueue.main.async { self.bttvChannelMap = map }
        } catch { /*print("BTTV channel load error: \(error)") */}
    }

    // Комплексная загрузка эмоутов (7TV/BTTV/Twitch) и построение карты
    func loadGlobalEmotes() async {
        await load7TVEmotes()
        await load7TVChannelEmotes(channelLogin: TWITCH_CHANNEL)
        await loadBTTVGlobalEmotes()
        await loadBTTVChannelEmotes(channelLogin: TWITCH_CHANNEL)
        let url = URL(string: "https://api.twitch.tv/helix/chat/emotes/global")!
        var req = URLRequest(url: url)
        addHelixHeaders(&req)
        struct Response: Decodable { let data: [Emote] }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
//            if let http = resp as? HTTPURLResponse {
//                print("[TwitchChat] helix chat/emotes/global status: \(http.statusCode)")
//            }
            let result = try JSONDecoder().decode(Response.self, from: data)
            var map: [String: String] = [:]
            for emote in result.data {
                var url = emote.images.url_1x
                if let format = emote.format, format.contains("animated") {
                    url = url.replacingOccurrences(of: "/static/", with: "/animated/")
                }
                map[emote.name] = url
            }
            DispatchQueue.main.async {
                self.emoteMap = map
            }
        } catch {
            print("Ошибка загрузки смайликов: \(error)")
        }
    }

    // Разбивает сообщение на токены и заменяет известные эмоуты на .emote
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
        if let url = emoteMap[word] {
            return .emote(name: word, url: url, animated: false)
        }
        if let entry = stvChannelEmoteMap[word] {
            return .emote(name: word, url: entry.url, animated: entry.animated)
        }
        if let url = stvEmoteMap[word] {
            return .emote(name: word, url: url, animated: false)
        }
        if let url = bttvChannelMap[word] {
            return .emote(name: word, url: url, animated: false)
        }
        if let url = bttvGlobalMap[word] {
            return .emote(name: word, url: url, animated: false)
        }
        return nil
    }

    private func flushTextBuffer(_ buffer: inout [String], to result: inout [MessagePart]) {
        guard !buffer.isEmpty else { return }
        result.append(.text(buffer.joined(separator: " ")))
        buffer.removeAll()
    }

    // Преобразование HEX-строки в SwiftUI Color (поддержка #RGB и #RRGGBB)
    private func colorFromHex(_ hex: String) -> Color {
        let hexSanitized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        if hexSanitized.count == 3 {
            let r = String(repeating: hexSanitized[hexSanitized.startIndex], count: 2)
            let g = String(repeating: hexSanitized[hexSanitized.index(hexSanitized.startIndex, offsetBy: 1)], count: 2)
            let b = String(repeating: hexSanitized[hexSanitized.index(hexSanitized.startIndex, offsetBy: 2)], count: 2)
            let fullHex = r + g + b
            guard let int = UInt64(fullHex, radix: 16) else { return .primary }
            let red = Double((int >> 16) & 0xFF) / 255.0
            let green = Double((int >> 8) & 0xFF) / 255.0
            let blue = Double(int & 0xFF) / 255.0
            return Color(red: red, green: green, blue: blue)
        }
        guard hexSanitized.count == 6,
              let int = UInt64(hexSanitized, radix: 16) else {
            return .primary
        }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    /// Выполнение POST /helix/eventsub/subscriptions c нужными заголовками
    private func subscribeToEventSub(sessionId: String) async {
        // Этап 0: определить user_id (broadcaster)
        var targetUserId: String = self.channelId ?? ""
        if targetUserId.isEmpty {
            if let id = try? await TwitchChatManager.sharedChannelId(login: TWITCH_CHANNEL) { targetUserId = id }
        }
        guard !targetUserId.isEmpty else {
            print("[EventSub] Не удалось определить user_id для подписки")
            return
        }

        // Этап 1: список целевых типов событий, которые хотим иметь активными
        let desiredTypes: [String] = [
            "channel.channel_points_custom_reward_redemption.add",
            "channel.chat.message"
        ]

        // Этап 1: Получаем активные подписки и собираем множество типов
        var activeTypes = Set<String>()
        do {
            let getURL = URL(string: "https://api.twitch.tv/helix/eventsub/subscriptions?status=enabled")!
            var getReq = URLRequest(url: getURL)
            getReq.httpMethod = "GET"
            getReq.addValue("Bearer \(TWITCH_HELIX_BEARER_TOKEN)", forHTTPHeaderField: "Authorization")
            getReq.addValue(TWITCH_HELIX_CLIENT_ID, forHTTPHeaderField: "Client-Id")
            let (getData, getResp) = try await URLSession.shared.data(for: getReq)
            if let http = getResp as? HTTPURLResponse {
//                print("[EventSub] GET subscriptions status: \(http.statusCode)")
            }
            struct GetRoot: Decodable { struct Item: Decodable { let type: String? }; let data: [Item]? }
            if let decoded = try? JSONDecoder().decode(GetRoot.self, from: getData), let items = decoded.data {
                
                for it in items {
                    print("[EventSub] __________________________: \(it)")
                    if let t = it.type, !t.isEmpty { activeTypes.insert(t) }
                }
            }
        } catch {
            print("[EventSub] GET subscriptions error: \(error)")
            // Даже если GET не удался — попробуем подписаться на все желаемые типы
        }

        // Этап 2: Для каждого отсутствующего типа выполняем отдельный POST
        for t in desiredTypes where !activeTypes.contains(t) {
            do {
                let url = URL(string: "https://api.twitch.tv/helix/eventsub/subscriptions")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.addValue("Bearer \(TWITCH_HELIX_BEARER_TOKEN)", forHTTPHeaderField: "Authorization")
                req.addValue(TWITCH_HELIX_CLIENT_ID, forHTTPHeaderField: "Client-Id")
                req.addValue("application/json", forHTTPHeaderField: "Content-Type")

                // Сформируем тело запроса для конкретного type, переиспользуя текущие условия
                let bodyData = try buildEventSubSubscriptionBody(sessionId: sessionId, userId: targetUserId, overrideType: t)

                if let jsonObject = try? JSONSerialization.jsonObject(with: bodyData, options: []),
                   let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
                   let prettyString = String(data: prettyData, encoding: .utf8) {
//                    print("[EventSub] subscribe request body (JSON) for type=\(t):\n\(prettyString)")
                    print("[EventSub] +++++++++++++++++++++++++ type=\(t):\n\(prettyString)")
                }

                req.httpBody = bodyData
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse {
                    print("[EventSub] subscribe status for type=\(t): \(http.statusCode)")
                }
                if let body = String(data: data, encoding: .utf8) {
                    print("[EventSub] subscribe response for type=\(t): \(body)")
                }
            } catch {
                print("[EventSub] subscribe error for type=\(t): \(error)")
                // Переходим к следующему типу, не прерываем цикл
            }
        }
    }
}

extension TwitchChatManager {
    /// Рекурсивный поиск строкового значения по ключу в произвольном JSON (Dictionary/Array)
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

    /// Чистая функция: подключается к EventSub WebSocket, обрабатывает welcome, пинг/понг и подписки.
    func startEventSubWebSocket() {
        // Если уже есть активная задача — не дублируем
        if let task = eventSubWebSocketTask {
            switch task.state {
            case .running, .suspended:
                return
            default: break
            }
        }
        let task = urlSession.webSocketTask(with: eventSubURL)
        eventSubWebSocketTask = task
        task.resume()
        listenEventSubMessages()
    }

    /// Рекурсивное чтение сообщений из WS и обработка типов (welcome/notification/keepalive/ping)
    private func listenEventSubMessages() {
        eventSubWebSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                print("[EventSub] receive error: \(error)")
                // Пробуем переподключиться через небольшую паузу
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { self.reconnectEventSub() }
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleEventSubJSONString(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleEventSubJSONString(text)
                    } else {
                        print("[EventSub] binary message (non-utf8) size=\(data.count)")
                    }
                @unknown default:
                    break
                }
                // Продолжаем слушать
                self.listenEventSubMessages()
            }
        }
    }

    /// Обработка текстового JSON сообщения EventSub
    private func handleEventSubJSONString(_ text: String) {
        // Печатаем всё, что приходит, для отладки
        print("[EventSub] <- \(text)")
        struct Envelope: Decodable {
            struct Metadata: Decodable { let message_type: String; let subscription_type: String? }
            struct Payload: Decodable {
                struct Session: Decodable { let id: String? }
                let session: Session?
                // Для нотификаций Twitch присылает поле `event` и `subscription`, но для нашей печати достаточно словаря
            }
            let metadata: Metadata
            let payload: Payload?
        }
        // Пинг/понг на уровне WS: Twitch для keepalive может прислать ping кадр, URLSession сам вызовет .receive(.ping),
        // но на практике Twitch EventSub посылает keepalive-сообщения. Мы также ответим на WS ping, если придёт.
        // URLSessionWebSocketTask автоматически отвечает на .ping только по нашему вызову sendPing. Обработаем вручную ниже.

        struct BudgesItem: Codable {
            let setId: String
            let id: String
            let info: String
            
            private enum CodingKeys: String, CodingKey {
                case setId = "set_id"
                case id
                case info
            }
        }
        
        // Попробуем декодировать конверт, чтобы вытащить welcome
        if let data = text.data(using: .utf8), let env = try? JSONDecoder().decode(Envelope.self, from: data) {
            let type = env.metadata.message_type
            let subType = env.metadata.subscription_type
            if type == "session_welcome" {
                if let id = env.payload?.session?.id {
                    self.eventSubSessionId = id
                    print("[EventSub] session_welcome. session_id=\(id)")
                    // После welcome отправляем подписку
                    Task { await self.subscribeToEventSub(sessionId: id) }
                }
            } else if type == "notification" {
                // Разбираем JSON и распределяем значения по полям моделей
                let jsonAny: Any? = {
                    if let data = text.data(using: .utf8) {
                        return try? JSONSerialization.jsonObject(with: data, options: [])
                    }
                    return nil
                }()
                if subType == "channel.channel_points_custom_reward_redemption.add" {
                    
                    
                    // Извлекаем значения по ключам (могут быть глубоко вложены)
                    let messageIdStr = jsonAny.flatMap { findStringValue(forKey: "message_id", in: $0) }
                    let userNameStr = jsonAny.flatMap { findStringValue(forKey: "user_name", in: $0) }
                    let titleStr = jsonAny.flatMap { findStringValue(forKey: "title", in: $0) }
                    // Готовим значения с запасными вариантами
                    let computedId = messageIdStr.flatMap { UUID(uuidString: $0) } ?? UUID()
                    let sender = userNameStr ?? "eventsub"
                    let baseText: String = {
                        if let t = titleStr, !t.isEmpty { return t } else {
                            return text.count > 120 ? String(text.prefix(120)) + "…" : text
                        }
                    }()
                    let messageText = "Получена награда — \(baseText)"
                    let badgeData = self.badgeViews(from: [], badgeUrlMap: self.allBadgeImages)
                    let notif = Notification(id: computedId, sender: sender, text: messageText, badges: [], senderColor: .gray, badgeViewData: badgeData)
                    let msg = Message(id: UUID(), sender: sender, text: messageText, badges: [], senderColor: .gray, badgeViewData: badgeData)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.notifications.append(notif)
                        self.messages.append(msg)
                        if self.messages.count > 20 { self.messages.removeFirst(self.messages.count - 20) }
                    }
                } else if subType == "channel.chat.message" {
                    guard let jsonDict = jsonAny as? [String: Any],
                          let payload = jsonDict["payload"] as? [String: Any],
                          let event = payload["event"] as? [String: Any],
                          let senderShown = event["chatter_user_name"] as? String,
                          let messageDict = event["message"] as? [String: Any],
                          let msgText = messageDict["text"] as? String else {
                        print("Не удалось извлечь необходимые данные из JSON")
                        return
                    }

                    let senderColorHex = event["color"] as? String
                    let color: Color? = (senderColorHex?.isEmpty == false) ? colorFromHex(senderColorHex!) : nil
                    let badges = event["badges"] as? [[String: Any]] ?? []
                    
//                    handleIncoming(message)
                    // Преобразуем badges [[String: Any]] -> [(String, String)] для совместимости с моделью Message
                    let badgePairs: [(String, String)] = badges.compactMap { dict in
                        guard let set = dict["set_id"] as? String, let version = dict["id"] as? String else { return nil }
                        return (set, version)
                    }
                    
                    let badgeViewData = badgeViews(from: badgePairs, badgeUrlMap: allBadgeImages)
                    setLastMessageThrottled(Message(sender: senderShown, text: msgText, badges: badgePairs, senderColor: color, badgeViewData: badgeViewData))
                }
            } else if type == "session_keepalive" {
                // Можно логировать или обновлять таймер
                print("[EventSub] keepalive")
            } else if type == "session_reconnect" {
                print("[EventSub] reconnect requested")
//                reconnectEventSub()
            }
        }
    }

    /// Отправка pong при необходимости (если придёт ping кадр на уровне WS)
    private func sendEventSubPong() {
        eventSubWebSocketTask?.sendPing { error in
            if let error { print("[EventSub] ping/pong send error: \(error)") }
        }
    }

    /// Принудительное переподключение WS
    private func reconnectEventSub() {
        eventSubWebSocketTask?.cancel(with: .goingAway, reason: nil)
        eventSubWebSocketTask = nil
        startEventSubWebSocket()
    }

    /// Отправка подписки на EventSub (пример: channel.follow v2)
    private func buildEventSubSubscriptionBody(sessionId: String, userId: String) throws -> Data {
        try buildEventSubSubscriptionBody(sessionId: sessionId, userId: userId, overrideType: "channel.channel_points_custom_reward_redemption.add")
    }

    /// Универсальный билдер тела подписки с возможностью указать `type`
    private func buildEventSubSubscriptionBody(sessionId: String, userId: String, overrideType: String) throws -> Data {
        struct Body: Encodable {
            struct Condition: Encodable { let broadcaster_user_id: String; let moderator_user_id: String; let user_id: String }
            struct Transport: Encodable { let method: String; let session_id: String }
            let type: String
            let version: String
            let condition: Condition
            let transport: Transport
        }
        let body = Body(
            type: overrideType,
            version: "1",
            condition: .init(broadcaster_user_id: userId, moderator_user_id: "84011517", user_id: "84011517"),
            transport: .init(method: "websocket", session_id: sessionId)
        )
        return try JSONEncoder().encode(body)
    }
}

// MARK: - Stream Info (название стрима, категория, постер категории)
extension TwitchChatManager {
    // Ответ Helix: пользователи/каналы/игры
    private struct UsersResponse: Decodable {
        struct User: Decodable { let id: String }
        let data: [User]
    }
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
        struct Game: Decodable {
            let id: String
            let name: String
            let box_art_url: String
        }
        let data: [Game]
    }
    
    // Фоновый цикл: получение channelId и периодическое обновление информации о стриме
    fileprivate func runStreamInfoLoop() async {
//        print("[TwitchChat] runStreamInfoLoop() start. channelId=\(channelId ?? "nil")")
        if channelId == nil {
            if let id = try? await TwitchChatManager.sharedChannelId(login: TWITCH_CHANNEL) {
//                print("[TwitchChat] fetched channelId=\(id)")
                self.channelId = id
            } else {
                print("[TwitchChat] fetchChannelId failed")
            }
        }
        while !Task.isCancelled {
//            print("[TwitchChat] refreshStreamInfo() tick")
            await refreshStreamInfo()
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
        }
        print("[TwitchChat] runStreamInfoLoop() cancelled")
    }
    
    // Применяет заголовок и категорию в @Published полях (MainActor)
    @MainActor
    private func applyChannel(title: String, gameName: String) {
        if self.streamTitle != title {
            self.streamTitle = title
//            print("Название трансляции: \(title)")
        }
        if self.categoryName != gameName {
            self.categoryName = gameName
//            print("Категория: \(gameName)")
        }
    }
    
    // Применяет URL обложки категории (MainActor)
    @MainActor
    private func applyGameImage(url: URL?) {
        if self.categoryImageURL != url {
            self.categoryImageURL = url
//            if let url { print("[TwitchChat] Обновлён постер категории: \(url.absoluteString)") }
//            else { print("[TwitchChat] Постер категории сброшен (пустая категория)") }
        }
    }
    
    // Запрашивает /channels и /games для обновления заголовка/категории/обложки
    private func refreshStreamInfo() async {
        do {
            if channelId == nil {
//                print("[TwitchChat] channelId отсутствует — пробуем получить")
                channelId = try await TwitchChatManager.sharedChannelId(login: TWITCH_CHANNEL)
//                print("[TwitchChat] channelId получен: \(channelId!)")
            }
            guard let id = channelId else { return }
            
            // /helix/channels — получаем название и категорию
            let chURL = URL(string: "https://api.twitch.tv/helix/channels?broadcaster_id=\(id)")!
            var chReq = URLRequest(url: chURL)
            addHelixHeaders(&chReq)
            let (chData, chResp) = try await URLSession.shared.data(for: chReq)
//            if let http = chResp as? HTTPURLResponse {
//                print("[TwitchChat] helix/channels status: \(http.statusCode)")
//            }
            let chRespDecoded = try JSONDecoder().decode(ChannelsResponse.self, from: chData)
            guard let channel = chRespDecoded.data.first else {
                print("[TwitchChat] helix/channels: пустой ответ data")
                return
            }
            
            await applyChannel(title: channel.title, gameName: channel.game_name)
            
            // /helix/games — получаем box_art_url
            if !channel.game_id.isEmpty {
                let gURL = URL(string: "https://api.twitch.tv/helix/games?id=\(channel.game_id)")!
                var gReq = URLRequest(url: gURL)
                addHelixHeaders(&gReq)
                let (gData, gResp) = try await URLSession.shared.data(for: gReq)
//                if let http = gResp as? HTTPURLResponse {
//                    print("[TwitchChat] helix/games status: \(http.statusCode)")
//                }
                let gRespDecoded = try JSONDecoder().decode(GamesResponse.self, from: gData)
                let boxTemplate = gRespDecoded.data.first?.box_art_url ?? ""
                let boxURLString = boxTemplate
                    .replacingOccurrences(of: "{width}", with: "300")
                    .replacingOccurrences(of: "{height}", with: "450")
                let finalURL = URL(string: boxURLString)
                await applyGameImage(url: finalURL)
            } else {
                await applyGameImage(url: nil)
            }
        } catch {
            print("Ошибка обновления информации о стриме: \(error)")
        }
    }
}

// Удобный инициализатор для Message с автогенерацией UUID
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

// Представление сообщения для отображения (с рассчитанными частями и усечением)
struct DisplayMessage: Identifiable {
    let id = UUID()
    let badges: [BadgeViewData]
    let sender: String
    let senderColor: Color
    let visibleParts: [MessagePart]
    let isTruncated: Bool
}

// MARK: - SwiftUI-вью для отображения сообщения: бейджи, ник, текст/эмоута
















