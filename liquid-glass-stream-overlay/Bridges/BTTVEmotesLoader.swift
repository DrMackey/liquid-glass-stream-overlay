import Foundation

func load7TVEmotes(manager: TwitchChatManager) async {
    let url = URL(string: "https://7tv.io/v3/emote-sets/global")!
    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        struct GlobalEmoteResponse: Decodable { let emotes: [STVEmote] }
        let decoded = try JSONDecoder().decode(GlobalEmoteResponse.self, from: data)
        var map: [String: String] = [:]
        for emote in decoded.emotes {
            if let url = emote.url(size: "1x", format: "WEBP") { map[emote.name] = url }
        }
        DispatchQueue.main.async { manager.stvEmoteMap = map }
    } catch {}
}

func load7TVChannelEmotes(channelLogin: String, manager: TwitchChatManager) async {
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
        DispatchQueue.main.async { manager.stvChannelEmoteMap = map }
    } catch { print("Ошибка загрузки 7TV channel emotes: \(error)") }
}
