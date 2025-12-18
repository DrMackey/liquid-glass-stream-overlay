import SwiftUI
import AppKit

// MARK: - SwiftUI-вью для отображения сообщения: бейджи, ник, текст/эмоута
struct MessageTextView: View {
    let badges: [BadgeViewData]
    let sender: String
    let senderColor: Color
    let parts: [MessagePart]
    let maxWidth: CGFloat
    let badgeViews: ([(String, String)]) -> [BadgeViewData]
    let isTruncated: Bool
    
    // Внутренняя структура с уже рассчитанными данными для рисования
    private struct ProcessedMessage {
        let visibleParts: [MessagePart]
        let isTruncated: Bool
        let badges: [BadgeViewData]
        let sender: String
        let senderColor: Color
    }
    // Ленивая подготовка данных: проверка входных параметров
    private var processedMessage: ProcessedMessage? {
        guard !parts.isEmpty, !badges.isEmpty, !sender.isEmpty else { return nil }
        guard maxWidth > 0 else { return nil }
        return ProcessedMessage(
            visibleParts: parts,
            isTruncated: isTruncated,
            badges: badges,
            sender: sender,
            senderColor: senderColor
        )
    }
    // Ключ анимации: зависит от отправителя и видимых частей
    private var animationKey: String {
        guard let processed = processedMessage else { return "none" }
        return processed.sender + String(processed.visibleParts.hashValue)
    }
    // Состояния анимации и буфера сообщений
    @State private var isExpanded: Bool = false
    @Namespace private var namespace
    @State private var lastSender: String? = nil
    // Убрали буфер и флаг анимации
    @State private var activeMessage: ProcessedMessage? = nil
    @State private var badgeWidth: CGFloat = 0

    // Локальная версия расчёта видимых частей для данной платформы
    private func calculateVisibleParts(parts: [MessagePart], font: NSFont, maxWidth: CGFloat) -> ([MessagePart], Bool) {
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

    // Прямая обработка последнего сообщения без буфера
    private func processNextMessage(_ next: ProcessedMessage) {
        // Если отправитель меняется — делаем сворачивание/разворачивание бейджей
        if lastSender == nil || lastSender != next.sender {
            withAnimation { isExpanded = false }
            let transitionDuration = 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) {
                lastSender = next.sender
                activeMessage = next
                withAnimation { isExpanded = true }
            }
        } else {
            // Тот же отправитель — просто обновляем контент
            activeMessage = next
        }
    }
    // Подвью: бейджи + ник в стекле
    struct BadgeAndNickView: View {
        let badgeViewsArray: [BadgeViewData]
        let senderText: Text
        var body: some View {
            // Рендерим все бейджи и ник с эффектом стекла
            HStack(spacing: 6) {
                ForEach(badgeViewsArray) { badge in
                    if let url = badge.url {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView().frame(width: 32, height: 32)
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fit).frame(width: 32, height: 32)
                            case .failure:
                                Text("❓").frame(width: 32, height: 32)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Text("❓").frame(width: 32, height: 32)
                    }
                }
                senderText
            }
            .opacity(0.9)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 0)
            .padding()
            .glassEffect(.regular)
        }
    }
    // Подвью: строка частей сообщения (текст/эмуоты) с усечением
    struct MessagePartsRowView: View {
        let visiblePartsArray: [MessagePart]
        let isTruncated: Bool
        var body: some View {
            // Рендерим последовательность частей и добавляем многоточие при усечении
            HStack(spacing: 2) {
                ForEach(visiblePartsArray.indices, id: \.self) { index in
                    let part = visiblePartsArray[index]
                    switch part {
                    case .text(let string):
                        let isLast = index == visiblePartsArray.count - 1
                        let addSpace = !(isLast && isTruncated)
                        Text(string + (addSpace ? " " : ""))
                            .foregroundColor(.white)
                    case .emote(_, let urlStr, let animated):
                        if let url = URL(string: urlStr) {
                            EmoteImageView(url: url, size: 32, animated: animated)
                        }
                    }
                }
                if isTruncated {
                    Text("…")
                        .foregroundColor(.white)
                        .font(.system(size: 32))
                        .fontWeight(.bold)
                }
            }
            .opacity(0.9)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 0)
            .padding()
            .glassEffect(.regular)
            .glassEffectTransition(.materialize)
        }
    }
    var body: some View {
        // Основной контент: стек из блока бейджей/ника и строки сообщения
        if let showMsg = activeMessage ?? processedMessage {
            GlassEffectContainer(spacing: 10.0) {
                // Контент с анимацией разворота бейджей при смене отправителя
                HStack(spacing: 8) {
                    if isExpanded {
                        BadgeAndNickView(
                            badgeViewsArray: showMsg.badges,
                            senderText: Text(showMsg.sender).foregroundColor(showMsg.senderColor).font(.system(size: 32))
                        )
                    }
                    MessagePartsRowView(visiblePartsArray: showMsg.visibleParts, isTruncated: showMsg.isTruncated)
                        .id(animationKey)
                        .font(.system(size: 32))
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: animationKey)
            }
            // Реакция на смену отправителя: берём последнее processedMessage напрямую
//            .onChange(of: processedMessage?.sender) { _ in
//                guard let processed = processedMessage else { return }
//                processNextMessage(processed)
//            }
            // Вызов при любом обновлении ProcessedMessage (по ключу анимации)
            .onChange(of: animationKey) { _ in
                if let processed = processedMessage {
                    processNextMessage(processed)
                }
            }
            // Начальная инициализация локальных состояний
            .onAppear {
                isExpanded = true
                lastSender = processedMessage?.sender
                activeMessage = processedMessage
            }
        } else {
            // Пока нет данных для отображения
            ProgressView()
                .frame(maxWidth: 16, maxHeight: 16)
                .padding()
                .glassEffect(.regular)
        }
    }
}
