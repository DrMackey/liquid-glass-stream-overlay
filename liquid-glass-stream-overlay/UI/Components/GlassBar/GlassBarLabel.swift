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
    var isNotifictaion: Bool = false
    // New external animation transition parameters with sensible defaults matching previous behavior
    var insertionTransition: AnyTransition = .scale.combined(with: .opacity)
    var removalTransition: AnyTransition = .move(edge: .bottom).combined(with: .opacity)
    let stackingThreshold: CGFloat = 200
    let maxVisibleMessages = 12
    let spacing: CGFloat = 16
    @Namespace private var messageAnim

    @State private var messageHeights: [TwitchChatManager.Message.ID: CGFloat] = [:]
    
    // ДОБАВЬТЕ ЭТУ ПЕРЕМЕННУЮ: для отслеживания последнего обработанного сообщения
    @State private var lastProcessedMessageId: TwitchChatManager.Message.ID? = nil

    // MARK: - Computation helpers to reduce type-checking complexity
    private func messagesSource(availableMessages: [TwitchChatManager.Message], availableNotifications: [TwitchChatManager.Message], isNotification: Bool) -> [TwitchChatManager.Message] {
        if isNotification { return availableNotifications }
        return availableMessages
    }

    private func computeOffsets(for messages: [TwitchChatManager.Message], messageHeights: [TwitchChatManager.Message.ID: CGFloat], spacing: CGFloat) -> [CGFloat] {
        var result: [CGFloat] = []
        result.reserveCapacity(messages.count)
        var currentOffset: CGFloat = 0
        for message in messages {
            result.append(currentOffset)
            let height: CGFloat = messageHeights[message.id] ?? 48
            currentOffset += height + spacing
        }
        return result
    }

    private func visibleIndices(offsets: [CGFloat], messages: [TwitchChatManager.Message], availableHeight: CGFloat, messageHeights: [TwitchChatManager.Message.ID: CGFloat]) -> [Int] {
        var indices: [Int] = []
        indices.reserveCapacity(messages.count)
        for (idx, offset) in offsets.enumerated() {
            let message = messages[idx]
            let height: CGFloat = messageHeights[message.id] ?? 48
            if offset + height <= availableHeight { indices.append(idx) }
        }
        return indices
    }

    var body: some View {
        GeometryReader { geo in
            let availableHeight: CGFloat = geo.size.height
            let baseMessages: [TwitchChatManager.Message] = Array(chat.messages.suffix(maxVisibleMessages).reversed())
            let baseNotificationsRaw = Array(chat.notifications.suffix(maxVisibleMessages).reversed())

            // Map notifications to Message explicitly to reduce inference work
            let notificationsAsMessages: [TwitchChatManager.Message] = baseNotificationsRaw.map { notif in
                TwitchChatManager.Message(
                    id: notif.id,
                    sender: notif.sender,
                    text: notif.text,
                    badges: notif.badges,
                    senderColor: notif.senderColor,
                    badgeViewData: notif.badgeViewData
                )
            }

            let messages: [TwitchChatManager.Message] = messagesSource(
                availableMessages: baseMessages,
                availableNotifications: notificationsAsMessages,
                isNotification: isNotifictaion
            )

            let offsets: [CGFloat] = computeOffsets(
                for: messages,
                messageHeights: messageHeights,
                spacing: spacing
            )

            let visIndices: [Int] = visibleIndices(
                offsets: offsets,
                messages: messages,
                availableHeight: availableHeight,
                messageHeights: messageHeights
            )

            let visibleMessages: [TwitchChatManager.Message] = visIndices.map { messages[$0] }
            
            ZStack(alignment: .top) {
                ForEach(visibleMessages) { message in
                    let idx = visibleMessages.firstIndex(where: { $0.id == message.id }) ?? 0
                    let y = offsets[visIndices[idx]]
                    
                    Group {
                        let display = DisplayMessage(
                            badges: message.badgeViewData,
                            sender: message.sender,
                            senderColor: (message.sender == "system" ? .gray : (message.senderColor ?? .red)),
                            visibleParts: chat.parseMessageWithEmotes(message.text),
                            isTruncated: false
                        )
                        let layout = MessageLayout(message: display, index: idx, isCollapsed: false, stackPosition: idx)
                        CollapsibleMessageView(
                            layout: layout,
                            maxWidth: geo.size.width,
                            totalCount: visibleMessages.count,
                            contentPaddingH: 24,
                            contentPaddingV: 20,
                            bubbleCornerRadius: 32
                        )
                        .matchedGeometryEffect(id: message.id, in: messageAnim)
                        .offset(y: y)
                        .transition(.asymmetric(insertion: insertionTransition, removal: removalTransition))
                        .background(
                            GeometryReader { geoMsg in
                                Color.clear
                                    .preference(key: MessageHeightKey.self, value: [message.id: geoMsg.size.height])
                            }
                        )
                    }
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
            .onChange(of: visibleMessages.first?.id) { newFirstId in
                guard isNotifictaion else { return }
                guard let newId = newFirstId else { return }
                if newId != lastProcessedMessageId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        SoundPlayer.playSound(sound: "notification", type: "mp3")
                    }
                    lastProcessedMessageId = newId
                }
            }
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
