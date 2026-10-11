import Foundation

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

    @MainActor
    private func applyChannel(title: String, gameName: String) {
        if streamTitle != title { streamTitle = title }
        if categoryName != gameName { categoryName = gameName }
    }

    @MainActor
    private func applyGameImage(url: URL?) {
        if categoryImageURL != url { categoryImageURL = url }
    }

    /// Однократная выборка данных о стриме через Helix `/channels`.
    ///
    /// Вызывается по фронту подключения EventSub (первый коннект и каждое
    /// восстановление после разрыва), а не по таймеру: пока соединение живо,
    /// заголовок и категорию обновляет событие `channel.update`.
    func refreshStreamInfo() async {
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

            applyChannel(title: channel.title, gameName: channel.game_name)

            let gameId = channel.game_id.isEmpty ? nil : channel.game_id
            categoryId = gameId
            if let gameId {
                applyGameImage(url: await gameBoxArtURL(gameId: gameId))
            } else {
                applyGameImage(url: nil)
            }
        } catch {
            print("Ошибка обновления информации о стриме: \(error)")
        }
    }

    /// Тихий приём `channel.update`: применяет заголовок и категорию из события,
    /// а постер категории догружает только при смене `category_id`.
    ///
    /// Событие не показывается уведомлением — только обновляет данные о стриме.
    @MainActor
    func applyStreamUpdate(_ update: StreamUpdateEvent) {
        if streamTitle != update.title { streamTitle = update.title }
        if let gameName = update.category_name, categoryName != gameName {
            categoryName = gameName
        }

        let newCategoryId = update.category_id.flatMap { $0.isEmpty ? nil : $0 }
        guard let newCategoryId, newCategoryId != categoryId else { return }
        categoryId = newCategoryId
        Task { [weak self] in
            guard let self else { return }
            let url = await self.gameBoxArtURL(gameId: newCategoryId)
            self.applyGameImage(url: url)
        }
    }

    /// Загружает постер категории по её идентификатору (Helix `/games`).
    private func gameBoxArtURL(gameId: String) async -> URL? {
        guard let gURL = URL(string: "https://api.twitch.tv/helix/games?id=\(gameId)") else { return nil }
        var gReq = URLRequest(url: gURL)
        addHelixHeaders(&gReq)
        guard let (gData, _) = try? await URLSession.shared.data(for: gReq),
              let boxTemplate = (try? JSONDecoder().decode(GamesResponse.self, from: gData))?.data.first?.box_art_url,
              !boxTemplate.isEmpty else {
            return nil
        }
        return URL(string: boxTemplate
            .replacingOccurrences(of: "{width}", with: "300")
            .replacingOccurrences(of: "{height}", with: "450"))
    }
}

