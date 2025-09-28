import SwiftUI
import Combine
import Foundation
import Network
import SDWebImageSwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

let TWITCH_CHANNEL = "PWGood"

// Константы Helix API (по примеру curl: Client-Id + Bearer)
// При необходимости подставьте свои значения.
let TWITCH_HELIX_CLIENT_ID = "gp762nuuoqcoxypju8c569th9wz7q5"
let TWITCH_HELIX_BEARER_TOKEN = "2s4x0c089w8u5ouwdoi5veduxk9sbr"

/// Представляет часть сообщения: текст или эмот.
enum MessagePart: Hashable {
    case text(String)
    case emote(name: String, url: String, animated: Bool)
}

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

// Реализация EmoteImageView для отображения gif-по-URL или AsyncImage для обычных картинок
struct EmoteImageView: View {
    let url: URL
    let size: CGFloat
    let animated: Bool // Добавлен параметр animated для определения анимации
    
    var body: some View {
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
                        ProgressView().frame(width: size, height: size)
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

#if os(macOS)
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
#endif

// Для отображения бейджиков
struct BadgeViewData: Identifiable, Hashable, Equatable {
    let id = UUID()
    let set: String
    let version: String
    let url: URL?
}

final class TwitchChatManager: ObservableObject {
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

    @Published var lastMessage: Message?
    @Published var messages: [Message] = []

    @Published var allBadgeImages: [String: [String: String]] = [:]
    @Published var emoteMap: [String: String] = [:]
    @Published var stvEmoteMap: [String: String] = [:]
    @Published var stvChannelEmoteMap: [String: (url: String, animated: Bool)] = [:]
    @Published var bttvGlobalMap: [String: String] = [:]
    @Published var bttvChannelMap: [String: String] = [:]
    
    // Новые опубликованные значения для GlassBarContainer
    @Published var streamTitle: String = ""
    @Published var categoryName: String = ""
    @Published var categoryImageURL: URL? = nil

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

    init() {
        print("[TwitchChat] init()")
        // Стартуем фоновое обновление информации о стриме/категории
        streamInfoTask = Task { [weak self] in
            await self?.runStreamInfoLoop()
        }
    }

    deinit {
        print("[TwitchChat] deinit()")
        streamInfoTask?.cancel()
    }
    
    // Единое добавление Helix-заголовков (по примеру curl)
    private func addHelixHeaders(_ request: inout URLRequest) {
        // Здесь подставляется Client-Id из TWITCH_HELIX_CLIENT_ID и Bearer-токен
        request.addValue("Bearer \(TWITCH_HELIX_BEARER_TOKEN)", forHTTPHeaderField: "Authorization")
        request.addValue(TWITCH_HELIX_CLIENT_ID, forHTTPHeaderField: "Client-Id")
    }

    func badgeViews(from badges: [(String, String)], badgeUrlMap: [String: [String: String]]) -> [BadgeViewData] {
        badges.map { (set, version) -> BadgeViewData in
            let url = badgeUrlMap[set]?[version].flatMap { URL(string: $0) }
            return BadgeViewData(set: set, version: version, url: url)
        }
    }

    func start() {
        print("[TwitchChat] start() called — запускаем IRC соединение")
        // ВАЖНО: stop() отменяет streamInfoTask. Мы сразу после stop() перезапустим её ниже.
        stop()
        let host = NWEndpoint.Host("irc.chat.twitch.tv")
        let port = NWEndpoint.Port(rawValue: 6697)!
        connection = NWConnection(host: host, port: port, using: .tls)
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[TwitchChat] IRC connection ready")
                self?.sendCredentials()
                self?.receiveMessages()
            case .failed(let error):
                print("[TwitchChat] IRC connection failed: \(error)")
                let badgeViewData = self?.badgeViews(from: [], badgeUrlMap: self?.allBadgeImages ?? [:]) ?? []
                self?.setLastMessageThrottled(Message(sender: "system", text: "Connection failed: \(error.localizedDescription)", badges: [], senderColor: Color.gray, badgeViewData: badgeViewData))
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    self?.start()
                }
            case .waiting(let error):
                print("[TwitchChat] IRC connection waiting: \(error)")
                let badgeViewData = self?.badgeViews(from: [], badgeUrlMap: self?.allBadgeImages ?? [:]) ?? []
                self?.setLastMessageThrottled(Message(sender: "system", text: "Connection waiting: \(error.localizedDescription)", badges: [], senderColor: Color.gray, badgeViewData: badgeViewData))
            case .cancelled:
                print("[TwitchChat] IRC connection cancelled")
                let badgeViewData = self?.badgeViews(from: [], badgeUrlMap: self?.allBadgeImages ?? [:]) ?? []
                self?.setLastMessageThrottled(Message(sender: "system", text: "Connection cancelled", badges: [], senderColor: Color.gray, badgeViewData: badgeViewData))
            default:
                break
            }
        }
        connection?.start(queue: queue)
        // Перезапускаем фоновую задачу получения информации о стриме, если она была отменена stop()
        if streamInfoTask == nil {
            streamInfoTask = Task { [weak self] in
                await self?.runStreamInfoLoop()
            }
        }
    }

    private func sendCredentials() {
        print("[TwitchChat] sendCredentials()")
        guard let connection = connection else { return }
        send("CAP REQ :twitch.tv/tags\r\n")
        let commands = [
            "PASS \(oauthToken)\r\n",
            "NICK \(nick)\r\n",
            "JOIN #\(TWITCH_CHANNEL)\r\n"
        ]
        for command in commands {
            send(command)
        }
    }

    private func send(_ string: String) {
        guard let connection = connection else { return }
        let data = Data(string.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func receiveMessages() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] (data, _, isComplete, error) in
            if let data = data, !data.isEmpty, let message = String(data: data, encoding: .utf8) {
                self?.handleIncoming(message)
            }
            if isComplete == false {
                self?.receiveMessages()
            }
        }
    }

    private func parseIrcTags(_ tags: String) -> [String: String] {
        var result: [String: String] = [:]
        let noAt = tags.hasPrefix("@") ? String(tags.dropFirst()) : tags
        for pair in noAt.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                result[String(kv[0])] = String(kv[1])
            }
        }
        return result
    }

    private func handleIncoming(_ message: String) {
        if message.hasPrefix("PING") {
            send("PONG :tmi.twitch.tv\r\n")
            return
        }
        let lines = message.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        for line in lines {
            var badges: [(String, String)] = []
            var senderColor: Color? = nil
            var display_name: String? = nil
            var restOfLine = line
            if restOfLine.hasPrefix("@") {
                if let spaceIndex = restOfLine.firstIndex(of: " ") {
                    let tagsPart = String(restOfLine[..<spaceIndex])
                    let tagsDict = parseIrcTags(tagsPart)
                    restOfLine = String(restOfLine[restOfLine.index(after: spaceIndex)...])
                    if let badgesString = tagsDict["badges"], !badgesString.isEmpty {
                        badges = badgesString.split(separator: ",").compactMap {
                            let parts = $0.split(separator: "/")
                            if parts.count == 2 {
                                return (String(parts[0]), String(parts[1]))
                            }
                            return nil
                        }
                    }
                    if let colorString = tagsDict["color"], !colorString.isEmpty {
                        senderColor = colorFromHex(colorString)
                    }
                    if let displayName = tagsDict["display-name"], !displayName.isEmpty {
                        display_name = displayName
                    }
                }
            }
            if restOfLine.contains(" PRIVMSG ") {
                if let prefixRange = restOfLine.range(of: ":"),
                   let exclamRange = restOfLine.range(of: "!"),
                   prefixRange.lowerBound == restOfLine.startIndex,
                   exclamRange.lowerBound > prefixRange.lowerBound {
                    let sender = String(restOfLine[restOfLine.index(after: prefixRange.lowerBound)..<exclamRange.lowerBound])
                    if let messageRange = restOfLine.range(of: " :") {
                        let msgText = String(restOfLine[messageRange.upperBound...])
                        let senderShown = display_name ?? sender
                        let badgeViewData = badgeViews(from: badges, badgeUrlMap: allBadgeImages)
                        setLastMessageThrottled(Message(sender: senderShown, text: msgText, badges: badges, senderColor: senderColor, badgeViewData: badgeViewData))
                    }
                }
            }
        }
    }

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

    func stop() {
        print("[TwitchChat] stop() — останавливаем IRC и фоновые задачи")
        connection?.cancel()
        connection = nil
        displayTimer?.invalidate()
        displayTimer = nil
        pendingMessage = nil
        // Останавливаем фоновые обновления информации о стриме
        streamInfoTask?.cancel()
        streamInfoTask = nil // чтобы в start() можно было создать новую задачу
    }

    func loadAllBadges(channelLogin: String) async {
        var mergedBadges: [String: [String: String]] = [:]
        do {
            let urlGlobal = URL(string: "https://api.twitch.tv/helix/chat/badges/global")!
            var reqGlobal = URLRequest(url: urlGlobal)
            addHelixHeaders(&reqGlobal)
            let (dataGlobal, resp) = try await URLSession.shared.data(for: reqGlobal)
            if let http = resp as? HTTPURLResponse {
                print("[TwitchChat] badges/global status: \(http.statusCode)")
            }
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
            let userURL = URL(string: "https://api.twitch.tv/helix/users?login=\(channelLogin)")!
            var userRequest = URLRequest(url: userURL)
            addHelixHeaders(&userRequest)
            let (userData, resp) = try await URLSession.shared.data(for: userRequest)
            if let http = resp as? HTTPURLResponse {
                print("[TwitchChat] users?login= status: \(http.statusCode)")
            }
            struct UserResponse: Decodable { struct User: Decodable { let id: String }; let data: [User] }
            let decodedUser = try JSONDecoder().decode(UserResponse.self, from: userData)
            guard let userId = decodedUser.data.first?.id else { return }
            let badgeURL = URL(string: "https://api.twitch.tv/helix/chat/badges?broadcaster_id=\(userId)")!
            var badgeRequest = URLRequest(url: badgeURL)
            addHelixHeaders(&badgeRequest)
            let (badgeData, resp2) = try await URLSession.shared.data(for: badgeRequest)
            if let http = resp2 as? HTTPURLResponse {
                print("[TwitchChat] chat/badges?broadcaster_id= status: \(http.statusCode)")
            }
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

    func load7TVEmotes() async {
        let url = URL(string: "https://7tv.io/v3/emote-sets/global")!
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse {
                print("[TwitchChat] 7TV global status: \(http.statusCode)")
            }
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
            print("Ошибка загрузки 7tv смайликов: \(error)")
        }
    }

    func load7TVChannelEmotes(channelLogin: String) async {
        let userUrl = URL(string: "https://api.ivr.fi/v2/twitch/user?login=\(channelLogin)")!
        do {
            let (userData, userHTTPResp) = try await URLSession.shared.data(from: userUrl)
            if let http = userHTTPResp as? HTTPURLResponse {
                print("[TwitchChat] IVR user status: \(http.statusCode)")
            }
            struct User: Decodable { let id: String }
            let userObj = try JSONDecoder().decode([User].self, from: userData)
            guard let userId = userObj.first?.id else { return }
            let setUrl = URL(string: "https://7tv.io/v3/users/twitch/\(userId)")!
            let (data, resp2) = try await URLSession.shared.data(from: setUrl)
            if let http = resp2 as? HTTPURLResponse {
                print("[TwitchChat] 7TV user set status: \(http.statusCode)")
            }
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

    func loadBTTVGlobalEmotes() async {
        let url = URL(string: "https://api.betterttv.net/3/cached/emotes/global")!
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse {
                print("[TwitchChat] BTTV global status: \(http.statusCode)")
            }
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
            let (userData, userHTTPResp) = try await URLSession.shared.data(from: userUrl)
            if let http = userHTTPResp as? HTTPURLResponse {
                print("[TwitchChat] IVR user (BTTV) status: \(http.statusCode)")
            }
            struct User: Decodable { let id: String }
            let userObj = try JSONDecoder().decode([User].self, from: userData)
            guard let userId = userObj.first?.id else { return }
            let url = URL(string: "https://api.betterttv.net/3/cached/users/twitch/\(userId)")!
            let (data, bttvHTTPResp) = try await URLSession.shared.data(from: url)
            if let http = bttvHTTPResp as? HTTPURLResponse {
                print("[TwitchChat] BTTV user status: \(http.statusCode)")
            }
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
        } catch { print("BTTV channel load error: \(error)") }
    }

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
            if let http = resp as? HTTPURLResponse {
                print("[TwitchChat] helix chat/emotes/global status: \(http.statusCode)")
            }
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

    func parseMessageWithEmotes(_ text: String) -> [MessagePart] {
        let words = text.split(separator: " ")
        return words.map { w in
            let s = String(w)
            if let url = emoteMap[s] {
                return .emote(name: s, url: url, animated: false)
            } else if let stvChannelEntry = stvChannelEmoteMap[s] {
                return .emote(name: s, url: stvChannelEntry.url, animated: stvChannelEntry.animated)
            } else if let url = stvEmoteMap[s] {
                return .emote(name: s, url: url, animated: false)
            } else if let url = bttvChannelMap[s] {
                return .emote(name: s, url: url, animated: false)
            } else if let url = bttvGlobalMap[s] {
                return .emote(name: s, url: url, animated: false)
            } else {
                return .text(s)
            }
        }
    }

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
}

// MARK: - Stream Info (название стрима, категория, постер категории)
extension TwitchChatManager {
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
    
    // Фоновый цикл: первично получает channelId, затем опрашивает Helix каждые 30 сек
    fileprivate func runStreamInfoLoop() async {
        print("[TwitchChat] runStreamInfoLoop() start. channelId=\(channelId ?? "nil")")
        if channelId == nil {
            if let id = try? await fetchChannelId(login: TWITCH_CHANNEL) {
                print("[TwitchChat] fetched channelId=\(id)")
                self.channelId = id
            } else {
                print("[TwitchChat] fetchChannelId failed")
            }
        }
        while !Task.isCancelled {
            print("[TwitchChat] refreshStreamInfo() tick")
            await refreshStreamInfo()
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
        }
        print("[TwitchChat] runStreamInfoLoop() cancelled")
    }
    
    private func fetchChannelId(login: String) async throws -> String {
        // ВАЖНО: Twitch логины — в нижнем регистре
        let url = URL(string: "https://api.twitch.tv/helix/users?login=\(login.lowercased())")!
        var req = URLRequest(url: url)
        addHelixHeaders(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse {
            print("[TwitchChat] helix/users status: \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(UsersResponse.self, from: data)
        guard let id = decoded.data.first?.id else {
            throw URLError(.badServerResponse)
        }
        return id
    }
    
    @MainActor
    private func applyChannel(title: String, gameName: String) {
        if self.streamTitle != title {
            self.streamTitle = title
            print("Название трансляции: \(title)")
        }
        if self.categoryName != gameName {
            self.categoryName = gameName
            print("Категория: \(gameName)")
        }
    }
    
    @MainActor
    private func applyGameImage(url: URL?) {
        if self.categoryImageURL != url {
            self.categoryImageURL = url
            if let url { print("[TwitchChat] Обновлён постер категории: \(url.absoluteString)") }
            else { print("[TwitchChat] Постер категории сброшен (пустая категория)") }
        }
    }
    
    private func refreshStreamInfo() async {
        do {
            if channelId == nil {
                print("[TwitchChat] channelId отсутствует — пробуем получить")
                channelId = try await fetchChannelId(login: TWITCH_CHANNEL)
                print("[TwitchChat] channelId получен: \(channelId!)")
            }
            guard let id = channelId else { return }
            
            // /helix/channels — получаем название и категорию
            let chURL = URL(string: "https://api.twitch.tv/helix/channels?broadcaster_id=\(id)")!
            var chReq = URLRequest(url: chURL)
            addHelixHeaders(&chReq)
            let (chData, chResp) = try await URLSession.shared.data(for: chReq)
            if let http = chResp as? HTTPURLResponse {
                print("[TwitchChat] helix/channels status: \(http.statusCode)")
            }
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
                if let http = gResp as? HTTPURLResponse {
                    print("[TwitchChat] helix/games status: \(http.statusCode)")
                }
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

struct DisplayMessage: Identifiable {
    let id = UUID()
    let badges: [BadgeViewData]
    let sender: String
    let senderColor: Color
    let visibleParts: [MessagePart]
    let isTruncated: Bool
}

extension TwitchChatManager {
    func makeDisplayMessage(_ message: Message, maxWidth: CGFloat, badgeUrlMap: [String: [String: String]]) -> DisplayMessage {
        let badgeData = message.badgeViewData
        let parts = parseMessageWithEmotes(message.text)
#if os(macOS)
        let font = NSFont.systemFont(ofSize: 32, weight: .bold)
#else
        let font = UIFont.systemFont(ofSize: 32, weight: .bold)
#endif
        let (visibleParts, isTruncated) = calculateVisibleParts(parts: parts, font: font, maxWidth: maxWidth)
        return DisplayMessage(
            badges: badgeData,
            sender: message.sender,
            senderColor: message.sender == "system" ? .gray : (message.senderColor ?? .red),
            visibleParts: visibleParts,
            isTruncated: isTruncated
        )
    }
    func calculateVisibleParts(parts: [MessagePart], font: Any, maxWidth: CGFloat) -> ([MessagePart], Bool) {
#if os(macOS)
        let fnt = font as! NSFont
#else
        let fnt = font as! UIFont
#endif
        var width: CGFloat = 0
        var visibleParts: [MessagePart] = []
        for part in parts {
            let partWidth: CGFloat
            switch part {
            case .text(let str):
                partWidth = str.size(withAttributes: [.font: fnt]).width + fnt.pointSize * 0.3
            case .emote:
                partWidth = 32
            }
            if width + partWidth > maxWidth {
                switch part {
                case .text(let str):
                    let remainingWidth = maxWidth - width
                    if remainingWidth <= 0 {
                        return (visibleParts, true)
                    }
                    var low = 0
                    var high = str.count
                    var fittingLength = 0
                    while low <= high {
                        let mid = (low + high) / 2
                        let prefix = String(str.prefix(mid))
                        let prefixWidth = prefix.size(withAttributes: [.font: fnt]).width + fnt.pointSize * 0.3
                        if prefixWidth <= remainingWidth {
                            fittingLength = mid
                            low = mid + 1
                        } else {
                            high = mid - 1
                        }
                    }
                    if fittingLength > 0 {
                        let fittingPrefix = String(str.prefix(fittingLength))
                        visibleParts.append(.text(fittingPrefix))
                    }
                    return (visibleParts, true)
                case .emote:
                    return (visibleParts, true)
                }
            }
            visibleParts.append(part)
            width += partWidth
        }
        return (visibleParts, false)
    }
}

// MessageTextView + subviews
struct MessageTextView: View {
    let badges: [BadgeViewData]
    let sender: String
    let senderColor: Color
    let parts: [MessagePart]
    let maxWidth: CGFloat
    let badgeViews: ([(String, String)]) -> [BadgeViewData]
    let isTruncated: Bool
    
    private struct ProcessedMessage {
        let visibleParts: [MessagePart]
        let isTruncated: Bool
        let badges: [BadgeViewData]
        let sender: String
        let senderColor: Color
    }
    private var processedMessage: ProcessedMessage? {
        guard !parts.isEmpty, !badges.isEmpty, !sender.isEmpty else { return nil }
        guard maxWidth > 0 else { return nil }
        return ProcessedMessage(
            visibleParts: parts,
            isTruncated: isTruncated,
            badges: badges,
            sender: sender,
            senderColor: senderColor
        )
    }
    private var animationKey: String {
        guard let processed = processedMessage else { return "none" }
        return processed.sender + String(processed.visibleParts.hashValue)
    }
    @State private var isExpanded: Bool = false
    @Namespace private var namespace
    @State private var lastSender: String? = nil
    @State private var messageBuffer: [(sender: String, processed: ProcessedMessage)] = []
    @State private var activeMessage: (sender: String, processed: ProcessedMessage)? = nil
    @State private var isAnimating: Bool = false
    @State private var badgeWidth: CGFloat = 0
    #if os(macOS)
    private func calculateVisibleParts(parts: [MessagePart], font: NSFont, maxWidth: CGFloat) -> ([MessagePart], Bool) {
        var width: CGFloat = 0
        var visibleParts: [MessagePart] = []
        for part in parts {
            let partWidth: CGFloat
            switch part {
            case .text(let str):
                partWidth = str.size(withAttributes: [.font: font]).width + font.pointSize * 0.3
            case .emote:
                partWidth = 32
            }
            if width + partWidth > maxWidth {
                switch part {
                case .text(let str):
                    let remainingWidth = maxWidth - width
                    if remainingWidth <= 0 {
                        return (visibleParts, true)
                    }
                    var low = 0
                    var high = str.count
                    var fittingLength = 0
                    while low <= high {
                        let mid = (low + high) / 2
                        let prefix = String(str.prefix(mid))
                        let prefixWidth = prefix.size(withAttributes: [.font: font]).width + font.pointSize * 0.3
                        if prefixWidth <= remainingWidth {
                            fittingLength = mid
                            low = mid + 1
                        } else {
                            high = mid - 1
                        }
                    }
                    if fittingLength > 0 {
                        let fittingPrefix = String(str.prefix(fittingLength))
                        visibleParts.append(.text(fittingPrefix))
                    }
                    return (visibleParts, true)
                case .emote:
                    return (visibleParts, true)
                }
            }
            visibleParts.append(part)
            width += partWidth
        }
        return (visibleParts, false)
    }
    #else
    private func calculateVisibleParts(parts: [MessagePart], font: UIFont, maxWidth: CGFloat) -> ([MessagePart], Bool) {
        var width: CGFloat = 0
        var visibleParts: [MessagePart] = []
        for part in parts {
            let partWidth: CGFloat
            switch part {
            case .text(let str):
                partWidth = str.size(withAttributes: [.font: font]).width + font.pointSize * 0.3
            case .emote:
                partWidth = 32
            }
            if width + partWidth > maxWidth {
                switch part {
                case .text(let str):
                    let remainingWidth = maxWidth - width
                    if remainingWidth <= 0 {
                        return (visibleParts, true)
                    }
                    var low = 0
                    var high = str.count
                    var fittingLength = 0
                    while low <= high {
                        let mid = (low + high) / 2
                        let prefix = String(str.prefix(mid))
                        let prefixWidth = prefix.size(withAttributes: [.font: font]).width + font.pointSize * 0.3
                        if prefixWidth <= remainingWidth {
                            fittingLength = mid
                            low = mid + 1
                        } else {
                            high = mid - 1
                        }
                    }
                    if fittingLength > 0 {
                        let fittingPrefix = String(str.prefix(fittingLength))
                        visibleParts.append(.text(fittingPrefix))
                    }
                    return (visibleParts, true)
                case .emote:
                    return (visibleParts, true)
                }
            }
            visibleParts.append(part)
            width += partWidth
        }
        return (visibleParts, false)
    }
    #endif
    private func processNextMessageFromBuffer() {
        guard !messageBuffer.isEmpty else { isAnimating = false; return }
        let next = messageBuffer.removeFirst()
        if lastSender == nil || lastSender != next.sender {
            isAnimating = true
            withAnimation { isExpanded = false }
            let transitionDuration = 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) {
                lastSender = next.sender
                activeMessage = next
                withAnimation { isExpanded = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) {
                    isAnimating = false
                    processNextMessageFromBuffer()
                }
            }
        } else {
            activeMessage = next
            isAnimating = false
            processNextMessageFromBuffer()
        }
    }
    struct BadgeAndNickView: View {
        let badgeViewsArray: [BadgeViewData]
        let senderText: Text
        var body: some View {
            HStack(spacing: 6) {
                ForEach(badgeViewsArray) { badge in
                    if let url = badge.url {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView().frame(width: 32, height: 32)
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fit).frame(width: 32, height: 32)
                            case .failure:
                                Text("❓").frame(width: 32, height: 32)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Text("❓").frame(width: 32, height: 32)
                    }
                }
                senderText
            }
            .opacity(0.9)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 0)
            .padding()
            .glassEffect(.regular)
        }
    }
    struct MessagePartsRowView: View {
        let visiblePartsArray: [MessagePart]
        let isTruncated: Bool
        var body: some View {
            HStack(spacing: 2) {
                ForEach(visiblePartsArray.indices, id: \.self) { index in
                    let part = visiblePartsArray[index]
                    switch part {
                    case .text(let string):
                        let isLast = index == visiblePartsArray.count - 1
                        let addSpace = !(isLast && isTruncated)
                        Text(string + (addSpace ? " " : ""))
                            .foregroundColor(.white)
                    case .emote(_, let urlStr, let animated):
                        if let url = URL(string: urlStr) {
                            EmoteImageView(url: url, size: 32, animated: animated)
                        }
                    }
                }
                if isTruncated {
                    Text("…")
                        .foregroundColor(.white)
                        .font(.system(size: 32))
                        .fontWeight(.bold)
                }
            }
            .opacity(0.9)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 0)
            .padding()
            .glassEffect(.regular)
        }
    }
    var body: some View {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: 32, weight: .bold)
        #else
        let font = UIFont.systemFont(ofSize: 32, weight: .bold)
        #endif
        if let showMsg = activeMessage?.processed ?? processedMessage {
            GlassEffectContainer(spacing: 10.0) {
                HStack(spacing: 8) {
                    if isExpanded {
                        BadgeAndNickView(
                            badgeViewsArray: showMsg.badges,
                            senderText: Text(showMsg.sender).foregroundColor(showMsg.senderColor).font(.system(size: 32))
                        )
                    }
                    MessagePartsRowView(visiblePartsArray: showMsg.visibleParts, isTruncated: showMsg.isTruncated)
                        .id(animationKey)
                        .font(.system(size: 32))
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: animationKey)
            }
            .onChange(of: processedMessage?.sender) { newSender in
                guard let processed = processedMessage else { return }
                if isAnimating {
                    messageBuffer.append((sender: processed.sender, processed: processed))
                    return
                }
                if lastSender == nil {
                    messageBuffer.append((sender: processed.sender, processed: processed))
                    isAnimating = true
                    processNextMessageFromBuffer()
                    return
                }
                if lastSender != processed.sender {
                    messageBuffer.append((sender: processed.sender, processed: processed))
                    if !isAnimating {
                        isAnimating = true
                        processNextMessageFromBuffer()
                    }
                } else {
                    activeMessage = (sender: processed.sender, processed: processed)
                }
            }
            .onAppear {
                isExpanded = true
                lastSender = processedMessage?.sender
                messageBuffer = []
                activeMessage = nil
                isAnimating = false
            }
        } else {
            ProgressView()
                .frame(maxWidth: maxWidth, maxHeight: 32)
                .padding()
        }
    }
}
