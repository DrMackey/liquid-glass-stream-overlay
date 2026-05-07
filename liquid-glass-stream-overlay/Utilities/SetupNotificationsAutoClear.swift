import SwiftUI
import Combine
import Foundation
import Network
import SDWebImageSwiftUI
import AppKit

// MARK: - SwiftUI-вью для отображения сообщения: бейджи, ник, текст/эмоута
extension TwitchChatManager {
    // MARK: - Подготовка отображаемого сообщения и расчёт видимых частей
    func makeDisplayMessage(_ message: Message, maxWidth: CGFloat, badgeUrlMap: [String: [String: String]]) -> DisplayMessage {
        // Выбор платформенного шрифта для замеров
        let badgeData = message.badgeViewData
        let parts = parseMessageWithEmotes(message.text)
        let font = NSFont.systemFont(ofSize: 32, weight: .bold)
        // Вычисляем какие части помещаются в доступной ширине
        let (visibleParts, isTruncated) = calculateVisibleParts(parts: parts, font: font, maxWidth: maxWidth)
        return DisplayMessage(
            badges: badgeData,
            sender: message.sender,
            senderColor: message.sender == "system" ? .gray : (message.senderColor ?? .red),
            visibleParts: visibleParts,
            isTruncated: isTruncated
        )
    }
    // Подсчёт ширины частей и бинарный поиск по длине текста для усечения
    func calculateVisibleParts(parts: [MessagePart], font: Any, maxWidth: CGFloat) -> ([MessagePart], Bool) {
        // Платформенное приведение типа шрифта
        let fnt = font as! NSFont
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
