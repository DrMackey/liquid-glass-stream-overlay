// GlassBarLabel.swift
// Новый стек сообщений с измерением высот и раскладкой

import SwiftUI
import AVFoundation

struct SoundPlayer {
    static var audioPlayer: AVAudioPlayer?
    
    static func playSound(sound: String, type: String) {
        if let path = Bundle.main.path(forResource: sound, ofType: type) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                audioPlayer?.play()
            } catch {
                print("Ошибка воспроизведения звука: \(error.localizedDescription)")
            }
        }
    }
}

struct GlassBarLabel: View {
    @ObservedObject var chat: TwitchChatManager
    var isNotification: Bool = false
    // New external animation transition parameters with sensible defaults matching previous behavior
    var insertionTransition: AnyTransition = .scale.combined(with: .opacity)
    var removalTransition: AnyTransition = .move(edge: .bottom).combined(with: .opacity)
    let stackingThreshold: CGFloat = 200
    let maxVisibleMessages = NotificationConstants.maxVisibleItems
    let spacing: CGFloat = NotificationConstants.stackSpacing
    @Namespace private var messageAnim

    @State private var messageHeights: [UUID: CGFloat] = [:]

    // ДОБАВЬТЕ ЭТУ ПЕРЕМЕННУЮ: для отслеживания последнего обработанного сообщения
    @State private var lastProcessedMessageId: UUID? = nil

    /// Элемент стека: сообщение чата либо уведомление события.
    /// Раскладка (смещения, видимость, высоты) работает с `id`, не завязываясь на конкретный тип.
    private enum StackItem: Identifiable {
        case message(Message)
        case notification(Notification)

        var id: UUID {
            switch self {
            case .message(let message): return message.id
            case .notification(let notification): return notification.id
            }
        }
    }

    // MARK: - Computation helpers to reduce type-checking complexity

    /// Свежие элементы сверху, не больше `maxVisibleMessages`; набор зависит от режима.
    private func stackItems() -> [StackItem] {
        if isNotification {
            return Array(chat.notifications.suffix(maxVisibleMessages).reversed()).map { .notification($0) }
        }
        return Array(chat.messages.suffix(maxVisibleMessages).reversed()).map { .message($0) }
    }

    private func computeOffsets(for items: [StackItem], messageHeights: [UUID: CGFloat], spacing: CGFloat) -> [CGFloat] {
        var result: [CGFloat] = []
        result.reserveCapacity(items.count)
        var currentOffset: CGFloat = 0
        for item in items {
            result.append(currentOffset)
            let height: CGFloat = messageHeights[item.id] ?? NotificationConstants.defaultRowHeight
            currentOffset += height + spacing
        }
        return result
    }

    private func visibleIndices(offsets: [CGFloat], items: [StackItem], availableHeight: CGFloat, messageHeights: [UUID: CGFloat]) -> [Int] {
        var indices: [Int] = []
        indices.reserveCapacity(items.count)
        for (idx, offset) in offsets.enumerated() {
            let item = items[idx]
            let height: CGFloat = messageHeights[item.id] ?? NotificationConstants.defaultRowHeight
            if offset + height <= availableHeight { indices.append(idx) }
        }
        return indices
    }

    /// Строит представление одного элемента стека: сообщение чата или карточку уведомления.
    @ViewBuilder
    private func itemView(_ item: StackItem, width: CGFloat, index: Int, totalCount: Int) -> some View {
        switch item {
        case .message(let message):
            let isNotice = message.isNotice
            let display = DisplayMessage(
                badges: message.badgeViewData,
                sender: isNotice ? NotificationConstants.notificationSender : message.sender,
                senderColor: isNotice
                    ? NotificationConstants.notificationSenderColor
                    : (message.sender == "system" ? .gray : (message.senderColor ?? .red)),
                visibleParts: chat.parseMessageWithEmotes(message.text),
                isTruncated: false
            )
            let layout = MessageLayout(message: display, index: index, isCollapsed: false, stackPosition: index)

            HStack(alignment: .top, spacing: 8) {
                CollapsibleMessageView(
                    layout: layout,
                    maxWidth: width,
                    totalCount: totalCount,
                    contentPaddingH: NotificationConstants.cardPaddingH,
                    contentPaddingV: NotificationConstants.cardPaddingV,
                    bubbleCornerRadius: NotificationConstants.cardCornerRadius
                )
            }

        case .notification(let notification):
            NotificationCardView(
                notification: notification,
                maxWidth: width,
                contentPaddingH: NotificationConstants.cardPaddingH,
                contentPaddingV: NotificationConstants.cardPaddingV,
                bubbleCornerRadius: NotificationConstants.cardCornerRadius
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            let availableHeight: CGFloat = geo.size.height
            let items: [StackItem] = stackItems()

            let offsets: [CGFloat] = computeOffsets(
                for: items,
                messageHeights: messageHeights,
                spacing: spacing
            )

            let visIndices: [Int] = visibleIndices(
                offsets: offsets,
                items: items,
                availableHeight: availableHeight,
                messageHeights: messageHeights
            )

            let visibleItems: [StackItem] = visIndices.map { items[$0] }

            ZStack(alignment: .top) {
                ForEach(visibleItems) { item in
                    let idx = visibleItems.firstIndex(where: { $0.id == item.id }) ?? 0
                    let y = offsets[visIndices[idx]]

                    itemView(item, width: geo.size.width, index: idx, totalCount: visibleItems.count)
                        .matchedGeometryEffect(id: item.id, in: messageAnim)
                        .offset(y: y)
                        .transition(.asymmetric(insertion: insertionTransition, removal: removalTransition))
                        .background(
                            GeometryReader { geoMsg in
                                Color.clear
                                    .preference(key: ItemHeightKey.self, value: [item.id: geoMsg.size.height])
                            }
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onPreferenceChange(ItemHeightKey.self) { newHeights in
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
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: visibleItems.map(\.id))
            .onChange(of: visibleItems.first?.id, initial: false) { _, newFirstId in
                guard isNotification else { return }
                guard let newId = newFirstId else { return }
                if newId != lastProcessedMessageId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        SoundPlayer.playSound(sound: "notification", type: "mp3")
                    }
                    lastProcessedMessageId = newId
                }
            }
        }
    }

    private struct ItemHeightKey: PreferenceKey {
        static var defaultValue: [UUID: CGFloat] = [:]
        static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
            value.merge(nextValue()) { $1 }
        }
    }
}
