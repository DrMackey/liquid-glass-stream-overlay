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

    func runStreamInfoLoop() async {
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

