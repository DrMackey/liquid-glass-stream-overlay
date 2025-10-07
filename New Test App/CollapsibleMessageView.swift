// CollapsibleMessageView.swift
// Отрисовка одного сообщения с поддержкой каскадного состояния

import SwiftUI

struct MessageLayout {
    let message: DisplayMessage
    let index: Int
    let isCollapsed: Bool
    let stackPosition: Int
}

struct CollapsibleMessageView: View {
    let layout: MessageLayout
    let maxWidth: CGFloat
    let totalCount: Int
    var cascadeStyle: CascadeStyle? = nil
    
    var contentPaddingH: CGFloat = 12
    var contentPaddingV: CGFloat = 10
    var bubbleCornerRadius: CGFloat = 16
    
    enum CascadeStyle {
        case cascade1
        case cascade2
    }
    
    private var scaleEffect: CGFloat {
        switch cascadeStyle {
        case .cascade1: return 0.92
        case .cascade2: return 0.84
        default:
            if layout.isCollapsed {
                let collapsedIndex = totalCount - layout.index - 1
                switch collapsedIndex {
                case 0: return 0.92
                case 1: return 0.84
                default: return 0.76
                }
            } else { return 1.0 }
        }
    }
    
    private var yOffset: CGFloat {
        switch cascadeStyle {
        case .cascade1: return 20
        case .cascade2: return 40
        default:
            return 0
        }
    }
    
    private var opacity: Double {
        switch cascadeStyle {
        case .cascade1: return 0.92
        case .cascade2: return 0.6
        default:
            if layout.isCollapsed {
                let collapsedIndex = totalCount - layout.index - 1
                switch collapsedIndex {
                case 0: return 0.9
                case 1: return 0.8
                default: return 0.7
                }
            } else { return 1.0 }
        }
    }
    
    private var zIndex: Double { Double(totalCount - layout.index) }
    
    private var fontSize: CGFloat {
        #if os(macOS)
        let baseSize = NSFont.systemFontSize
        #else
        let baseSize = UIFont.systemFontSize
        #endif
        return baseSize * 2 * scaleEffect
    }
    
    private var emoteSize: CGFloat { fontSize }
    private var badgeSize: CGFloat { fontSize }

    @ViewBuilder
    private var messageContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            messageFirstLine
            additionalMessageLines
        }
    }
    
    @ViewBuilder
    private var messageFirstLine: some View {
        HStack(alignment: .top, spacing: 6) {
            BadgeIconsView(badges: layout.message.badges, scale: fontSize / 16)
            senderName
            firstLineParts
            Spacer()
        }
    }
    
    @ViewBuilder
    private var senderName: some View {
        Text(layout.message.sender)
            .bold()
            .foregroundColor(layout.message.senderColor)
            .font(.system(size: fontSize))
    }
    
    @ViewBuilder
    private var firstLineParts: some View {
        if let firstLine = wrappedLines.first {
            ForEach(firstLine.indices, id: \.self) { i in
                let part = firstLine[i]
                switch part {
                case .text(let string):
                    Text(string + " ")
                        .foregroundColor(.primary)
                        .font(.system(size: fontSize))
                case .emote(_, let urlStr, let animated):
                    if let url = URL(string: urlStr) {
                        EmoteImageView(url: url, size: emoteSize, animated: animated)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var additionalMessageLines: some View {
        ForEach(Array(wrappedLines.indices.dropFirst().enumerated()), id: \.offset) { lineIndex, originalIndex in
            HStack(spacing: 2) {
                let line = wrappedLines[originalIndex]
                ForEach(line.indices, id: \.self) { i in
                    let part = line[i]
                    switch part {
                    case .text(let string):
                        Text(string + " ")
                            .foregroundColor(.primary)
                            .font(.system(size: fontSize))
                    case .emote(_, let urlStr, let animated):
                        if let url = URL(string: urlStr) {
                            EmoteImageView(url: url, size: emoteSize, animated: animated)
                        }
                    }
                }
                if originalIndex == wrappedLines.indices.last && layout.message.isTruncated {
                    Text("…")
                        .font(.system(size: fontSize))
                }
            }
        }
    }
    
    private var wrappedLines: [[MessagePart]] {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: fontSize)
        #else
        let font = UIFont.systemFont(ofSize: fontSize)
        #endif
        
        #if os(macOS)
        let nicknameWidth = layout.message.sender.size(withAttributes: [.font: font]).width + font.pointSize * 0.3
        #else
        let nicknameWidth = (layout.message.sender as NSString).size(withAttributes: [.font: font]).width + font.pointSize * 0.3
        #endif
        
        let badgesTotalWidth = CGFloat(layout.message.badges.count) * badgeSize + CGFloat(max(layout.message.badges.count-1, 0)) * 2
        
        return wrapMessageParts(
            layout.message.visibleParts,
            font: font,
            maxWidth: maxWidth * 0.7,
            firstLinePrefixWidth: nicknameWidth + badgesTotalWidth + 8
        )
    }
    
#if os(macOS)
    private func wrapMessageParts(_ parts: [MessagePart], font: NSFont, maxWidth: CGFloat, firstLinePrefixWidth: CGFloat = 0) -> [[MessagePart]] {
        var lines: [[MessagePart]] = []
        var currentLine: [MessagePart] = []
        var isFirstLine = true
        var currentLineWidth: CGFloat = isFirstLine ? firstLinePrefixWidth : 0
        
        for part in parts {
            switch part {
            case .text(let str):
                let words = str.split(separator: " ", omittingEmptySubsequences: false)
                for (i, wordSub) in words.enumerated() {
                    let word = String(wordSub) + (i < words.count-1 ? " " : "")
                    let partWidth = word.size(withAttributes: [.font: font]).width + font.pointSize * 0.3
                    let effectiveWidth = isFirstLine ? maxWidth - currentLineWidth : maxWidth
                    
                    if currentLineWidth + partWidth > effectiveWidth && !currentLine.isEmpty {
                        lines.append(currentLine)
                        currentLine = [.text(word)]
                        currentLineWidth = partWidth
                        isFirstLine = false
                    } else {
                        currentLine.append(.text(word))
                        currentLineWidth += partWidth
                    }
                }
            case .emote:
                let partWidth: CGFloat = emoteSize
                let effectiveWidth = isFirstLine ? maxWidth - currentLineWidth : maxWidth
                
                if currentLineWidth + partWidth > effectiveWidth && !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = [part]
                    currentLineWidth = partWidth
                    isFirstLine = false
                } else {
                    currentLine.append(part)
                    currentLineWidth += partWidth
                }
            }
        }
        
        if !currentLine.isEmpty { lines.append(currentLine) }
        return lines
    }
#else
    private func wrapMessageParts(_ parts: [MessagePart], font: UIFont, maxWidth: CGFloat, firstLinePrefixWidth: CGFloat = 0) -> [[MessagePart]] {
        var lines: [[MessagePart]] = []
        var currentLine: [MessagePart] = []
        var isFirstLine = true
        var currentLineWidth: CGFloat = isFirstLine ? firstLinePrefixWidth : 0
        
        for part in parts {
            switch part {
            case .text(let str):
                let words = str.split(separator: " ", omittingEmptySubsequences: false)
                for (i, wordSub) in words.enumerated() {
                    let word = String(wordSub) + (i < words.count-1 ? " " : "")
                    let partWidth = word.size(withAttributes: [.font: font]).width + font.pointSize * 0.3
                    let effectiveWidth = isFirstLine ? maxWidth - currentLineWidth : maxWidth
                    
                    if currentLineWidth + partWidth > effectiveWidth && !currentLine.isEmpty {
                        lines.append(currentLine)
                        currentLine = [.text(word)]
                        currentLineWidth = partWidth
                        isFirstLine = false
                    } else {
                        currentLine.append(.text(word))
                        currentLineWidth += partWidth
                    }
                }
            case .emote:
                let partWidth: CGFloat = emoteSize
                let effectiveWidth = isFirstLine ? maxWidth - currentLineWidth : maxWidth
                
                if currentLineWidth + partWidth > effectiveWidth && !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = [part]
                    currentLineWidth = partWidth
                    isFirstLine = false
                } else {
                    currentLine.append(part)
                    currentLineWidth += partWidth
                }
            }
        }
        
        if !currentLine.isEmpty { lines.append(currentLine) }
        return lines
    }
#endif

    var body: some View {
        messageContent
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, contentPaddingH)
            .padding(.vertical, contentPaddingV)
            .glassEffect(.regular, in: .rect(cornerRadius: bubbleCornerRadius))
            .scaleEffect(scaleEffect)
            .offset(y: yOffset)
            .opacity(opacity)
            .zIndex(zIndex)
            .animation(.spring(response: 0.9, dampingFraction: 0.7), value: layout.isCollapsed)
    }
}
