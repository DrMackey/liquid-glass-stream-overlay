// GlassBarLabel.swift
// Новый стек сообщений с измерением высот и раскладкой

import SwiftUI

struct GlassBarLabel: View {
    @ObservedObject var chat: TwitchChatManager
    let stackingThreshold: CGFloat = 200
    let maxVisibleMessages = 12
    let spacing: CGFloat = 16
    @Namespace private var messageAnim

    @State private var messageHeights: [TwitchChatManager.Message.ID: CGFloat] = [:]

    var body: some View {
        GeometryReader { geo in
            let availableHeight = geo.size.height
            let messages = Array(chat.messages.suffix(maxVisibleMessages).reversed())

            let offsets: [CGFloat] = {
                var result: [CGFloat] = []
                var currentOffset: CGFloat = 0
                for message in messages {
                    result.append(currentOffset)
                    let height = messageHeights[message.id] ?? 48
                    currentOffset += height + spacing
                }
                return result
            }()

            let visibleIndices = offsets.enumerated().filter { idx, offset in
                let message = messages[idx]
                let height = messageHeights[message.id] ?? 48
                return offset + height <= availableHeight
            }.map { $0.offset }
            let visibleMessages = visibleIndices.map { messages[$0] }

            ZStack(alignment: .top) {
                ForEach(visibleMessages) { message in
                    let idx = visibleMessages.firstIndex(where: { $0.id == message.id }) ?? 0
                    let y = offsets[visibleIndices[idx]]
                    
                    CollapsibleMessageView(
                        layout: MessageLayout(
                            message: chat.makeDisplayMessage(message, maxWidth: geo.size.width * 0.95, badgeUrlMap: chat.allBadgeImages),
                            index: idx, isCollapsed: false, stackPosition: idx
                        ),
                        maxWidth: geo.size.width * 0.95,
                        totalCount: visibleMessages.count,
                        cascadeStyle: nil,
                        contentPaddingH: 24,
                        contentPaddingV: 20,
                        bubbleCornerRadius: 32
                    )
                    .matchedGeometryEffect(id: message.id, in: messageAnim)
                    .offset(y: y)
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .move(edge: .bottom).combined(with: .opacity)))
                    .background(
                        GeometryReader { geoMsg in
                            Color.clear
                                .preference(key: MessageHeightKey.self, value: [message.id: geoMsg.size.height])
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onPreferenceChange(MessageHeightKey.self) { newHeights in
                var changed = false
                for (key, height) in newHeights {
                    if messageHeights[key] != height {
                        messageHeights[key] = height
                        changed = true
                    }
                }
                if changed {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {}
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: visibleMessages.map(\.id))
            .onChange(of: visibleMessages.map(\.id)) { _ in }
        }
    }

    private struct MessageHeightKey: PreferenceKey {
        static var defaultValue: [TwitchChatManager.Message.ID: CGFloat] = [:]
        static func reduce(value: inout [TwitchChatManager.Message.ID: CGFloat], nextValue: () -> [TwitchChatManager.Message.ID: CGFloat]) {
            value.merge(nextValue()) { $1 }
        }
    }
}
