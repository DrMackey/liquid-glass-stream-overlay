import Foundation
import AppKit

/// Локальная версия расчёта видимых частей для данной платформы.
/// Возвращает массив видимых MessagePart и флаг усечения.
func calculateVisibleParts(parts: [MessagePart], font: NSFont, maxWidth: CGFloat) -> ([MessagePart], Bool) {
    var width: CGFloat = 0
    var visibleParts: [MessagePart] = []
    for part in parts {
        let partWidth: CGFloat
        switch part {
        case .text(let str):
            partWidth = str.size(withAttributes: [.font: font]).width + font.pointSize * 0.3
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
                    let prefixWidth = prefix.size(withAttributes: [.font: font]).width + font.pointSize * 0.3
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
