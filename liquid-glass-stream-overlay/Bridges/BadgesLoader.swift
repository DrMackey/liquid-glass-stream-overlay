import Foundation

// MARK: - Загрузка бейджей
func loadAllBadges(channelLogin: String, manager: TwitchChatManager) async {
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

    DispatchQueue.main.async { manager.allBadgeImages = mergedBadges }
}
