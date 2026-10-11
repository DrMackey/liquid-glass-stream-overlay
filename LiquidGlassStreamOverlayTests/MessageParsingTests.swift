// MessageParsingTests.swift
// Тесты разбора сообщения на текст/эмоут и усечения частей по ширине

import Foundation
import AppKit
import SwiftUI
import Testing

@testable import Liquid_Glass_Stream_Overlay

@Suite("Разбор и усечение сообщения")
@MainActor
struct MessageParsingTests {

    /// Менеджер нужен только как носитель карт эмоутов, поэтому сеть не
    /// поднимается: тесты не открывают соединений и не дёргают mock-сервер.
    private func withManager(_ body: (TwitchChatManager) -> Void) {
        let manager = TwitchChatManager(startNetwork: false)
        defer { manager.stop() }
        body(manager)
    }

    private static let font = NSFont.systemFont(ofSize: 32, weight: .bold)

    /// Замер, повторяющий логику продакшена: ширина текста плюс 30% кегля.
    private static func width(of part: MessagePart, font: NSFont) -> CGFloat {
        switch part {
        case .text(let str):
            return str.size(withAttributes: [.font: font]).width + font.pointSize * 0.3
        case .emote:
            return 32
        }
    }

    private static func width(of parts: [MessagePart], font: NSFont) -> CGFloat {
        parts.reduce(0) { $0 + width(of: $1, font: font) }
    }

    // MARK: - parseMessageWithEmotes

    @Test("Обычный текст без эмоутов остаётся одной текстовой частью")
    func plainTextStaysSinglePart() {
        withManager { manager in
            let parts = manager.parseMessageWithEmotes("привет стрим")
            #expect(parts == [.text("привет стрим")])
        }
    }

    @Test("Эмоут внутри текста разбивает его на три части")
    func emoteSplitsText() {
        withManager { manager in
            manager.emoteMap["KEKW"] = "https://cdn/kekw.png"
            let parts = manager.parseMessageWithEmotes("hello KEKW world")

            #expect(parts.count == 3)
            #expect(parts[0] == .text("hello"))
            #expect(parts[2] == .text("world"))
            guard case .emote(let name, let url, let animated) = parts[1] else {
                Issue.record("средняя часть должна быть эмоутом")
                return
            }
            #expect(name == "KEKW")
            #expect(url == "https://cdn/kekw.png")
            #expect(animated == false)
        }
    }

    @Test("Два эмоута подряд не склеиваются в текст")
    func consecutiveEmotesStaySeparate() {
        withManager { manager in
            manager.emoteMap["KEKW"] = "https://cdn/kekw.png"
            manager.emoteMap["PogChamp"] = "https://cdn/pog.png"

            let parts = manager.parseMessageWithEmotes("a KEKW PogChamp b")

            #expect(parts.count == 4)
            #expect(parts[0] == .text("a"))
            #expect(isEmote(parts[1], "KEKW"))
            #expect(isEmote(parts[2], "PogChamp"))
            #expect(parts[3] == .text("b"))
        }
    }

    @Test("Эмоут в начале и в конце сообщения")
    func emoteAtBothEnds() {
        withManager { manager in
            manager.emoteMap["KEKW"] = "https://cdn/kekw.png"

            let parts = manager.parseMessageWithEmotes("KEKW окей KEKW")

            #expect(parts.count == 3)
            #expect(isEmote(parts[0], "KEKW"))
            #expect(parts[1] == .text("окей"))
            #expect(isEmote(parts[2], "KEKW"))
        }
    }

    @Test("Интервалы схлопываются — текущее поведение парсера")
    func multipleSpacesCollapse() {
        withManager { manager in
            let parts = manager.parseMessageWithEmotes("а  б   в")
            #expect(parts == [.text("а б в")])
        }
    }

    @Test("Неизвестное слово остаётся текстом")
    func unknownWordIsText() {
        withManager { manager in
            #expect(manager.getEmote(for: "KEKW") == nil)
            #expect(manager.parseMessageWithEmotes("KEKW") == [.text("KEKW")])
        }
    }

    @Test("Порядок поиска эмоута: 7TV-канал → глобальные → BTTV")
    func emoteLookupOrder() {
        withManager { manager in
            // Заполняем все пять карт одним и тем же ключом.
            manager.emoteMap["X"] = "https://emote/x.png"
            manager.stvChannelEmoteMap["X"] = (url: "https://stv-channel/x.png", animated: true)
            manager.stvEmoteMap["X"] = "https://stv/x.png"
            manager.bttvChannelMap["X"] = "https://bttv-channel/x.png"
            manager.bttvGlobalMap["X"] = "https://bttv-global/x.png"

            #expect(emoteUrl(manager.getEmote(for: "X")) == "https://emote/x.png")

            manager.emoteMap.removeValue(forKey: "X")
            let stvChannel = manager.getEmote(for: "X")
            #expect(emoteUrl(stvChannel) == "https://stv-channel/x.png")
            #expect(emoteAnimated(stvChannel) == true)

            manager.stvChannelEmoteMap.removeValue(forKey: "X")
            #expect(emoteUrl(manager.getEmote(for: "X")) == "https://stv/x.png")

            manager.stvEmoteMap.removeValue(forKey: "X")
            #expect(emoteUrl(manager.getEmote(for: "X")) == "https://bttv-channel/x.png")

            manager.bttvChannelMap.removeValue(forKey: "X")
            #expect(emoteUrl(manager.getEmote(for: "X")) == "https://bttv-global/x.png")

            manager.bttvGlobalMap.removeValue(forKey: "X")
            #expect(manager.getEmote(for: "X") == nil)
        }
    }

    // MARK: - calculateVisibleParts

    @Test("Всё помещается — ничего не усечено")
    func everythingFits() {
        withManager { manager in
            let parts: [MessagePart] = [.text("short")]
            let (visible, truncated) = manager.calculateVisibleParts(
                parts: parts, font: Self.font, maxWidth: 1000
            )

            #expect(visible == parts)
            #expect(truncated == false)
        }
    }

    @Test("Нулевая ширина сразу обрезает всё")
    func zeroWidthTruncatesImmediately() {
        withManager { manager in
            let (visible, truncated) = manager.calculateVisibleParts(
                parts: [.text("hi")], font: Self.font, maxWidth: 0
            )

            #expect(visible.isEmpty)
            #expect(truncated == true)
        }
    }

    @Test("При нехватке ширины текст обрезается до префикса, который влезает")
    func textIsTruncatedToFit() {
        withManager { manager in
            let font = Self.font
            let text = String(repeating: "слово ", count: 40)
            let maxWidth: CGFloat = 200

            let (visible, truncated) = manager.calculateVisibleParts(
                parts: [.text(text)], font: font, maxWidth: maxWidth
            )

            #expect(truncated == true)
            #expect(visible.count == 1)
            guard case .text(let fitted)? = visible.first else {
                Issue.record("ожидалась усечённая текстовая часть")
                return
            }
            // Возврат — префикс исходной строки, а не обрезка посередине слова.
            #expect(text.hasPrefix(fitted))
            #expect(!fitted.isEmpty)
            // Бинарный поиск гарантирует, что влезшая часть не шире остатка.
            #expect(Self.width(of: .text(fitted), font: font) <= maxWidth)
        }
    }

    @Test("Эмоут, который не помещается, отбрасывается с флагом усечения")
    func overflowingEmoteIsDropped() {
        withManager { manager in
            let font = Self.font
            let longText = String(repeating: "очень длинный текст ", count: 30)
            // Ширины хватает ровно на текст, но не на эмоут после него.
            let textWidth = Self.width(of: .text(longText), font: font)

            let (visible, truncated) = manager.calculateVisibleParts(
                parts: [.text(longText), .emote(name: "KEKW", url: "u", animated: false)],
                font: font,
                maxWidth: textWidth + 1
            )

            #expect(truncated == true)
            #expect(visible.count == 1)
            #expect(visible[0] == .text(longText))
        }
    }

    @Test("Ширина всех видимых частей никогда не превышает заданную")
    func visibleWidthNeverExceedsMax() {
        withManager { manager in
            let font = Self.font
            let text = String(repeating: "проверка обрезки ", count: 50)

            for maxWidth in [0, 10, 50, 120, 400, 900] {
                let (visible, _) = manager.calculateVisibleParts(
                    parts: [.text(text)], font: font, maxWidth: CGFloat(maxWidth)
                )
                let measured = Self.width(of: visible, font: font)
                #expect(
                    measured <= CGFloat(maxWidth),
                    "при maxWidth=\(maxWidth) получено \(measured)"
                )
            }
        }
    }

    // MARK: - makeDisplayMessage

    @Test("makeDisplayMessage разбирает текст и переносит признак усечения")
    func makeDisplayMessageParsesAndTruncates() {
        withManager { manager in
            manager.emoteMap["KEKW"] = "https://cdn/kekw.png"
            let message = Message(
                id: UUID(),
                sender: "viewers",
                text: "привет KEKW",
                badges: [],
                senderColor: .red,
                badgeViewData: []
            )

            let display = manager.makeDisplayMessage(message, maxWidth: 4000)

            #expect(display.sender == "viewers")
            #expect(display.visibleParts.count == 2)
            #expect(display.visibleParts[0] == .text("привет"))
            #expect(isEmote(display.visibleParts[1], "KEKW"))
            #expect(display.isTruncated == false)
        }
    }

    @Test("Цвет отправителя: system → серый, без цвета → красный")
    func senderColorFallbacks() {
        withManager { manager in
            let wideEnough: CGFloat = 10_000

            let system = manager.makeDisplayMessage(
                Message(
                    id: UUID(),
                    sender: "system",
                    text: "x",
                    badges: [],
                    senderColor: nil,
                    badgeViewData: []
                ),
                maxWidth: wideEnough
            )
            #expect(system.senderColor == .gray)

            let unknown = manager.makeDisplayMessage(
                Message(
                    id: UUID(),
                    sender: "someone",
                    text: "x",
                    badges: [],
                    senderColor: nil,
                    badgeViewData: []
                ),
                maxWidth: wideEnough
            )
            #expect(unknown.senderColor == .red)
        }
    }

    @Test("Бейджи сообщения переходят в отображаемое без изменений")
    func badgesCarryThrough() {
        withManager { manager in
            let badges = [BadgeViewData(set: "moderator", version: "1", url: nil)]
            let display = manager.makeDisplayMessage(
                Message(
                    id: UUID(),
                    sender: "mod",
                    text: "hello",
                    badges: [],
                    senderColor: .red,
                    badgeViewData: badges
                ),
                maxWidth: 10_000
            )

            #expect(display.badges.count == 1)
            #expect(display.badges[0].set == "moderator")
            #expect(display.badges[0].version == "1")
        }
    }
}

// MARK: - Вспомогательные

private func isEmote(_ part: MessagePart, _ name: String) -> Bool {
    guard case .emote(let emoteName, _, _) = part else { return false }
    return emoteName == name
}

private func emoteUrl(_ part: MessagePart?) -> String? {
    guard case .emote(_, let url, _)? = part else { return nil }
    return url
}

private func emoteAnimated(_ part: MessagePart?) -> Bool? {
    guard case .emote(_, _, let animated)? = part else { return nil }
    return animated
}
