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
    let message: TwitchChatManager.Message
    
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
        guard !parts.isEmpty, !sender.isEmpty else { return nil }
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
    
    @State private var isExpanded: Bool = false
    @State private var isToggle: Bool = true
    @Namespace private var namespace
    @State private var lastSender: String? = nil
    @State private var activeMessage: ProcessedMessage? = nil
    @State private var badgeWidth: CGFloat = 0
    @State private var messages2: [MessagePart] = []
    @State private var currentIndex = 0

    // Подвью: бейджи + ник в стекле
    struct BadgeAndNickView: View {
        let badgeViewsArray: [BadgeViewData]
        let senderText: Text
        let namespace: Namespace.ID
        
        // Кешируем Data изображений вместо UIImage
        @State private var imageDataCache: [URL: Data] = [:]
        
        var body: some View {
            HStack(spacing: 6) {
                ForEach(badgeViewsArray) { badge in
                    if let url = badge.url {
                        if let imageData = imageDataCache[url] {
                            if let nsImage = NSImage(data: imageData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)
                            } else {
                                Text("❓").frame(width: 32, height: 32)
                            }
                        } else {
                            // Загружаем и кешируем
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView().frame(width: 32, height: 32)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 32, height: 32)
                                        .task {
                                            await cacheImageData(from: url)
                                        }
                                case .failure:
                                    Text("❓").frame(width: 32, height: 32)
                                @unknown default:
                                    EmptyView()
                                }
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
//            .glassEffectTransition(.matchedGeometry)
//            .glassEffectID("nick", in: namespace)
        }
        
        private func cacheImageData(from url: URL) async {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                await MainActor.run {
                    imageDataCache[url] = data
                }
            } catch {
                // Игнорируем ошибки кеширования
            }
        }
    }
    
    // Подвью: строка частей сообщения (текст/эмуоты) с усечением
    struct MessagePartsRowView: View {
            let visiblePartsArray: [MessagePart]
            let isTruncated: Bool
            var currentIndex: Int
            let animationKey: String
            let namespace: Namespace.ID
            
            var body: some View {
                HStack() {
                    // Рендерим последовательность частей и добавляем многоточие при усечении
                    HStack {
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
                    .transition(.blurReplace())
                    .id("msg-\(currentIndex)")
                    .opacity(0.9)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 0)
                    .padding()
                    .glassEffect(.regular)
//                    .glassEffectTransition(.matchedGeometry)
//                    .glassEffectID("message", in: namespace)
                }
                
                
            }
        }
    
    var body: some View {
        // Основной контент: стек из блока бейджей/ника и строки сообщения
        if let showMsg = processedMessage {
            GlassEffectContainer(spacing: 10.0) {
                // Контент с анимацией разворота бейджей при смене отправителя
                HStack(spacing: 8) {
                    if isExpanded, let active = activeMessage {
                        BadgeAndNickView(
                            badgeViewsArray: active.badges,
                            senderText: Text(active.sender).foregroundColor(active.senderColor).font(.system(size: 32)),
                            namespace: namespace
                        )
                    }
                    MessagePartsRowView(visiblePartsArray: messages2, isTruncated: showMsg.isTruncated, currentIndex: currentIndex, animationKey: animationKey, namespace: namespace)
                            .font(.system(size: 32))
                }
            }
            .onChange(of: animationKey) {
                withAnimation(.smooth(duration: 0.6)) {
                    currentIndex = (currentIndex + 1)
                    messages2 = showMsg.visibleParts
                }
                    
                if lastSender == nil || lastSender != processedMessage?.sender {
                    withAnimation(.smooth(duration: 0.6)) {
                        isExpanded = false
                    }
                    let transitionDuration = 0.3
                    DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) {
                        lastSender = processedMessage?.sender
                        activeMessage = processedMessage
                        withAnimation(.smooth(duration: 0.6)) {
                            isExpanded = true
                        }
                    }
                }
            }
            // Начальная инициализация локальных состояний
            .onAppear {
                messages2 = showMsg.visibleParts
                isExpanded = true
                lastSender = processedMessage?.sender
                activeMessage = processedMessage
            }
            Button("button") {
                withAnimation {
                    isExpanded.toggle()
                }
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

