import Foundation

func loadBTTVGlobalEmotes(manager: TwitchChatManager) async {
    let url = URL(string: "https://api.betterttv.net/3/cached/emotes/global")!
    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        struct Emote: Decodable { let code: String; let id: String }
        let emotes = try JSONDecoder().decode([Emote].self, from: data)
        var map: [String: String] = [:]
        for emote in emotes { map[emote.code] = "https://cdn.betterttv.net/emote/\(emote.id)/1x" }
        DispatchQueue.main.async { manager.bttvGlobalMap = map }
    } catch { print("BTTV global load error: \(error)") }
}

func loadBTTVChannelEmotes(channelLogin: String, manager: TwitchChatManager) async {
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
        DispatchQueue.main.async { manager.bttvChannelMap = map }
    } catch {}
}
