// MessageStackView.swift
// Стек сообщений с каскадом и вычислением переполнения

import SwiftUI

struct MessageStackView: View {
    let messages: [TwitchChatManager.Message]
    let availableHeight: CGFloat
    let maxWidth: CGFloat
    let chat: TwitchChatManager

    enum CascadeStyle {
        case cascade2
    }

    private struct Item {
        let display: DisplayMessage
        let height: CGFloat
    }

    private var messageItems: [Item] {
        let displays = messages.map { chat.makeDisplayMessage($0, maxWidth: maxWidth * 1000, badgeUrlMap: chat.allBadgeImages) }
        return displays.map { Item(display: $0, height: estimateMessageHeight($0, maxWidth: maxWidth)) }
    }

    private var fittingCount: Int {
        var used: CGFloat = 0
        let spacing: CGFloat = 8
        for (i, item) in messageItems.enumerated() {
            let next = used + item.height + (i > 0 ? spacing : 0)
            if next > availableHeight {
                return i
            }
            used = next
        }
        return messageItems.count
    }

    private var hasOverflow: Bool { fittingCount < messageItems.count }

    private var normalItems: [Item] {
        Array(messageItems.prefix(fittingCount > 0 ? fittingCount - (hasOverflow ? 1 : 0) : 0))
    }

    private var overflowItem: Item? {
        hasOverflow ? messageItems[fittingCount - 1] : nil
    }

    private func estimateMessageHeight(_ message: DisplayMessage, maxWidth: CGFloat) -> CGFloat {
        let baseHeight: CGFloat = 40
        let lineHeight: CGFloat = 20
        let estimatedLines = max(1, CGFloat(message.visibleParts.count) / 3)
        return baseHeight + (estimatedLines * lineHeight)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(normalItems, id: \.display.id) { item in
                    CollapsibleMessageView(
                        layout: MessageLayout(
                            message: item.display,
                            index: 0, isCollapsed: false, stackPosition: 0
                        ),
                        maxWidth: maxWidth,
                        totalCount: messageItems.count,
                        cascadeStyle: nil as CollapsibleMessageView.CascadeStyle?
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxHeight: availableHeight, alignment: .top)
            .clipped()
            if let item = overflowItem {
                CollapsibleMessageView(
                    layout: MessageLayout(
                        message: item.display,
                        index: 0, isCollapsed: true, stackPosition: 0
                    ),
                    maxWidth: maxWidth,
                    totalCount: messageItems.count,
                    cascadeStyle: CollapsibleMessageView.CascadeStyle.cascade2
                )
                .transition(.scale.combined(with: .opacity))
                .frame(maxWidth: .infinity, maxHeight: availableHeight, alignment: .bottom)
            }
        }
        .frame(maxHeight: availableHeight, alignment: .top)
        .clipped()
        .animation(.spring(response: 0.9, dampingFraction: 0.85), value: messages.count)
    }
}
