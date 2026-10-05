import Foundation

// MARK: - Модели ответа Helix для бейджей
//
// Типы объявлены на уровне файла, а не внутри функции: изоляция главного
// актора по умолчанию делает вложенные типы главноакторными, и из фоновой
// задачи `async let` их `Decodable`-соответствие использовать нельзя.
nonisolated struct BadgeVersion: Decodable {
    let id: String
    let image_url_2x: String?
}

nonisolated struct BadgeSet: Decodable {
    let set_id: String
    let versions: [BadgeVersion]
}

nonisolated struct BadgeHelixResponse: Decodable {
    let data: [BadgeSet]
}

// MARK: - Загрузка бейджей

/// Запрашивает наборы бейджей и возвращает их; при ошибке — пустой список.
///
/// Ошибка не считается критичной: приложение покажет чат без картинок бейджей,
/// поэтому она логируется и запрос прерывается, а не падает.
nonisolated private func fetchBadgeSets(from url: URL) async -> [BadgeSet] {
    var request = URLRequest(url: url)
    request.addValue("Bearer \(TWITCH_HELIX_BEARER_TOKEN)", forHTTPHeaderField: "Authorization")
    request.addValue(TWITCH_HELIX_CLIENT_ID, forHTTPHeaderField: "Client-Id")

    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(BadgeHelixResponse.self, from: data).data
    } catch {
        print("Ошибка загрузки бейджей (\(url.lastPathComponent)): \(error)")
        return []
    }
}

/// Загружает глобальные и канальные бейджи и складывает их в один словарь.
///
/// Глобальные и канальные наборы запрашиваются параллельно, а объединение
/// происходит после: одна и та же функция обслуживает оба запроса, поэтому
/// адрес и заголовки не расходятся между ветками.
func loadAllBadges(channelLogin: String, manager: TwitchChatManager) async {
    async let globalSets = fetchBadgeSets(
        from: URL(string: "https://api.twitch.tv/helix/chat/badges/global")!
    )

    async let channelSets = {
        let userId = (try? await TwitchChatManager.sharedChannelId(login: channelLogin)) ?? ""
        guard !userId.isEmpty else {
            print("Бейджи канала пропущены: не удалось определить user_id")
            return [BadgeSet]()
        }
        return await fetchBadgeSets(
            from: URL(string: "https://api.twitch.tv/helix/chat/badges?broadcaster_id=\(userId)")!
        )
    }()

    var mergedBadges: [String: [String: String]] = [:]

    for set in await (globalSets + channelSets) {
        var versions = mergedBadges[set.set_id] ?? [:]
        for version in set.versions {
            if let url = version.image_url_2x, !url.isEmpty {
                versions[version.id] = url
            }
        }
        if !versions.isEmpty {
            mergedBadges[set.set_id] = versions
        }
    }

    manager.allBadgeImages = mergedBadges
}