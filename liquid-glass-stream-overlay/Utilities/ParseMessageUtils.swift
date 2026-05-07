import Foundation

// MARK: - Парсинг сообщения с эмоутами
extension TwitchChatManager {
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
    
    func getEmote(for word: String) -> MessagePart? {
        
        if let url = emoteMap[word] { return .emote(name: word, url: url, animated: false) }
        if let entry = stvChannelEmoteMap[word] { return .emote(name: word, url: entry.url, animated: entry.animated) }
        if let url = stvEmoteMap[word] { return .emote(name: word, url: url, animated: false) }
        if let url = bttvChannelMap[word] { return .emote(name: word, url: url, animated: false) }
        if let url = bttvGlobalMap[word] { return .emote(name: word, url: url, animated: false) }
        return nil
    }
    
    func flushTextBuffer(_ buffer: inout [String], to result: inout [MessagePart]) {
        guard !buffer.isEmpty else { return }
        result.append(.text(buffer.joined(separator: " ")))
        buffer.removeAll()
    }
    
}
