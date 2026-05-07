import Foundation

// MARK: - Загрузка эмоутов (параллельно)
func loadTwitchGlobalEmotes(manager: TwitchChatManager) async {
    let url = URL(string: "https://api.twitch.tv/helix/chat/emotes/global")!
    var req = URLRequest(url: url)
    manager.addHelixHeaders(&req)
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
        DispatchQueue.main.async { manager.emoteMap = map }
    } catch {
        print("Ошибка загрузки смайликов Twitch: \(error)")
    }
}
