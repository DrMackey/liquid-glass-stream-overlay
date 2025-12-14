// CollapsibleMessageView.swift
// Отрисовка одного сообщения с поддержкой каскадного состояния

import SwiftUI

// Контейнер для компоновки одного сообщения.
struct MessageLayout {
    let message: DisplayMessage           // Данные сообщения
    let index: Int                       // Позиция сообщения в списке
    let isCollapsed: Bool               // Статус свернутости сообщения
    let stackPosition: Int              // Позиция для каскадного отображения
}

/*
 Представляет экранный элемент пузыря сообщения с поддержкой каскадного и свернутого отображения.
 Обрабатывает размеры, стили и визуальные эффекты в зависимости от состояния и стиля каскада.
*/
struct CollapsibleMessageView: View {
    let layout: MessageLayout           // Компоновка и данные сообщения для отображения
    let maxWidth: CGFloat               // Максимальная ширина области текста
    let totalCount: Int                // Общее количество сообщений в списке
    var contentPaddingH: CGFloat = 12  // Горизонтальные отступы внутри пузыря
    var contentPaddingV: CGFloat = 10  // Вертикальные отступы внутри пузыря
    var bubbleCornerRadius: CGFloat = 16  // Радиус скругления углов пузыря
    
    init(
        layout: MessageLayout,
        maxWidth: CGFloat,
        totalCount: Int,
        contentPaddingH: CGFloat = 12,
        contentPaddingV: CGFloat = 10,
        bubbleCornerRadius: CGFloat = 16
    ) {
        self.layout = layout
        self.maxWidth = maxWidth
        self.totalCount = totalCount
        self.contentPaddingH = contentPaddingH
        self.contentPaddingV = contentPaddingV
        self.bubbleCornerRadius = bubbleCornerRadius
    }
    
    /*
     Вычисляемый масштаб для сообщения.
     При свернутом состоянии масштаб зависит от позиции сообщения в стеке.
     В обычном состоянии — стандартный масштаб 1.0.
     Непосредственно влияет на размер текста и элементов.
    */
    private var scaleEffect: CGFloat {
        if layout.isCollapsed {
            let collapsedIndex = totalCount - layout.index - 1
            switch collapsedIndex {
            case 0: return 0.92
            case 1: return 0.84
            default: return 0.76
            }
        } else { return 1.0 }
    }
    
    /*
     Смещение по вертикали для сообщения.
     Без стилей каскада смещение отсутствует.
    */
    private var yOffset: CGFloat {
        0
    }
    
    /*
     Прозрачность сообщения.
     При свернутом состоянии зависит от позиции сообщения.
     В обычном состоянии — полностью непрозрачно.
    */
    private var opacity: Double {
        if layout.isCollapsed {
            let collapsedIndex = totalCount - layout.index - 1
            switch collapsedIndex {
            case 0: return 0.9
            case 1: return 0.8
            default: return 0.7
            }
        } else { return 1.0 }
    }
    
    /*
     Индекс слоя для правильного наложения при каскадном отображении.
     Чем меньше index, тем выше слой.
    */
    private var zIndex: Double { Double(totalCount - layout.index) }
    
    /*
     Вычисляет размер шрифта, масштабируя системный базовый размер с учетом масштаба.
     Влияет на читаемость и размер вложенных элементов.
    */
    private var fontSize: CGFloat {
        let baseSize: CGFloat = 13.0
        return baseSize * 2 * scaleEffect
    }
    
    /*
     Размер для эмодзи, равен размеру шрифта для гармоничного отображения.
    */
    private var emoteSize: CGFloat { fontSize }
    
    /*
     Размер для бейджей, равен размеру шрифта для консистентности.
    */
    private var badgeSize: CGFloat { fontSize }
    
    private struct FlowItem: Identifiable, Hashable {
        enum Kind: Hashable {
            case badges([BadgeViewData], scale: CGFloat)
            case sender(String, Color, size: CGFloat)
            case word(String, size: CGFloat) // одно слово или слово с пробелом в конце
            case emote(URL, size: CGFloat, animated: Bool)
        }
        enum StableID: Hashable {
            case badges(hash: Int, scale: Int)
            case sender(name: String, colorRGBA: UInt32, sizeKey: Int)
            case word(index: Int, text: String)
            case emote(url: String, animated: Bool)
        }
        let id: StableID
        let kind: Kind
    }

    private func buildFlowItems() -> [FlowItem] {
        enum LinearElement {
            case badges([BadgeViewData], scale: CGFloat)
            case sender(String, Color, size: CGFloat)
            case text(String, size: CGFloat)
            case emote(URL, size: CGFloat, animated: Bool)
        }

        var linear: [LinearElement] = []
        // badges
        linear.append(.badges(layout.message.badges, scale: fontSize / 16))
        // sender
        linear.append(.sender(layout.message.sender, layout.message.senderColor, size: fontSize))
        // parts in order
        for part in layout.message.visibleParts {
            switch part {
            case .text(let string):
                linear.append(.text(string, size: fontSize))
            case .emote(_, let urlStr, let animated):
                if let url = URL(string: urlStr) {
                    linear.append(.emote(url, size: emoteSize, animated: animated))
                }
            }
        }

        // Expand text into word tokens, adding trailing space only when next token is also a word
        var result: [FlowItem] = []
        var wordIndex = 0

        func appendWordTokens(from text: String, size: CGFloat, nextIsText: Bool) {
            // Split by whitespaces and newlines; ignore empty tokens
            // Preserve punctuation as part of the token
            let rawTokens = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            guard !rawTokens.isEmpty else { return }
            for i in 0..<rawTokens.count {
                let isLastInThisText = (i == rawTokens.count - 1)
                let shouldAppendSpace = !isLastInThisText || nextIsText
                let token = rawTokens[i] + (shouldAppendSpace ? " " : "")
                let sid: FlowItem.StableID = .word(index: wordIndex, text: token)
                result.append(.init(id: sid, kind: .word(token, size: size)))
                wordIndex += 1
            }
        }

        for (idx, element) in linear.enumerated() {
            let next = (idx + 1 < linear.count) ? linear[idx + 1] : nil
            switch element {
            case .badges(let badges, let scale):
                let badgesHash = badges.reduce(into: 0) { partial, b in
                    // Combine a few stable fields; adjust if BadgeViewData changes
                    partial = partial &* 31 &+ b.id.hashValue
                }
                let scaleKey = Int((scale * 1000).rounded())
                let sid: FlowItem.StableID = .badges(hash: badgesHash, scale: scaleKey)
                result.append(.init(id: sid, kind: .badges(badges, scale: scale)))
            case .sender(let name, let color, let size):
                let rgba = color.toRGBA32()
                let sizeKey = Int((size * 1000).rounded())
                let sid: FlowItem.StableID = .sender(name: name, colorRGBA: rgba, sizeKey: sizeKey)
                result.append(.init(id: sid, kind: .sender(name, color, size: size)))
            case .text(let string, let size):
                let nextIsText: Bool
                if case .text = next { nextIsText = true } else { nextIsText = false }
                appendWordTokens(from: string, size: size, nextIsText: nextIsText)
            case .emote(let url, let size, let animated):
                let sid: FlowItem.StableID = .emote(url: url.absoluteString, animated: animated)
                result.append(.init(id: sid, kind: .emote(url, size: size, animated: animated)))
            }
        }

        return result
    }
    
    private var messageContent: some View {
        FlowRows(items: buildFlowItems(), hSpacing: 6, vSpacing: 2, rowAlignment: .firstTextBaseline, spacingProvider: { current, next in
            // Если текущий и следующий элементы — слова, не добавляем межэлементный отступ, пробел уже входит в токен
            let currentIsWord: Bool
            let nextIsWord: Bool
            switch (current as! FlowItem).kind { case .word: currentIsWord = true; default: currentIsWord = false }
            if let next = next {
                switch (next as! FlowItem).kind { case .word: nextIsWord = true; default: nextIsWord = false }
            } else { nextIsWord = false }
            return (currentIsWord && nextIsWord) ? 0 : 6
        }) { item in
            switch item.kind {
            case .badges(let badges, let scale):
                BadgeIconsView(badges: badges, scale: scale)
            case .sender(let name, let color, let size):
                Text(name)
                    .bold()
                    .foregroundColor(color)
                    .font(.system(size: size))
                    .lineLimit(1)
//                    .background(Color.red)
            case .word(let token, let size):
                Text(token)
                    .foregroundColor(.primary)
                    .font(.system(size: size))
                    .lineLimit(1) // каждый токен — одна строка, перенос делаем на уровне лэйаута
//                    .background(Color.green)
            case .emote(let url, let size, let animated):
                EmoteImageView(url: url, size: size, animated: animated)
//                    .background(Color.red)
            }
        }
    }
    
    /*
     Основной body View.
     Составляет сообщение с настройками отступов, скругления, стековых эффектов, масштабирования, смещения,
     прозрачности и индекса слоя.
     Анимация зависит от изменений состояния свернутости.
    */
    var body: some View {
        messageContent
//            .fixedSize(horizontal: false, vertical: true)
//            .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - FlowRows: simple wrapping layout for inline items
private struct FlowRows<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let hSpacing: CGFloat
    let vSpacing: CGFloat
    let rowAlignment: VerticalAlignment
    let spacingProvider: ((Item, Item?) -> CGFloat)?

    @State private var sizes: [AnyHashable: CGSize] = [:]

    init(items: [Item], hSpacing: CGFloat = 8, vSpacing: CGFloat = 8, rowAlignment: VerticalAlignment = .firstTextBaseline, spacingProvider: ((Item, Item?) -> CGFloat)? = nil, @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.hSpacing = hSpacing
        self.vSpacing = vSpacing
        self.rowAlignment = rowAlignment
        self.spacingProvider = spacingProvider
        self.content = content
    }

    let content: (Item) -> Content
    @State private var onMaxHeight: CGFloat = 30
    

    var body: some View {
//        VStack() {
            GeometryReader { proxy in
                let availableWidth = proxy.size.width
                let rows = buildRows(maxWidth: availableWidth)
                
//                onMaxHeight *= CGFloat(rows.count)
                VStack(alignment: .leading, spacing: vSpacing) {
                    
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack( spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.element.id) { index, item in
                                let nextItem: Item? = (index + 1 < row.count) ? row[index + 1] : nil

                                content(item)
                                    .padding(.trailing, spacingBetween(item, nextItem))
                                    
                            }
                        }
                    }
                }
//                .onAppear { onMaxHeight = 30 * CGFloat(rows.count)
//                    print("Это переменная высоты: \(onMaxHeight): \(rows.count): \(rows)")}
                .onChange(of: rows.count) { if (rows.count > 1) {onMaxHeight = 30 * CGFloat(rows.count)} }
//                .frame(maxWidth: .infinity, alignment: .leading)
                // Hidden measuring layer to collect sizes
                .background(
                    ZStack { // keep ZStack only for measuring; items are hidden
                        ForEach(items) { item in
                            content(item)
                                .background(GeometryReader { geo in
                                    Color.clear.preference(key: _FlowItemSizeKey2.self, value: [AnyHashable(item.id): geo.size])
                                })
                                .hidden()
                        }
                    }
                )
                .onPreferenceChange(_FlowItemSizeKey2.self) { value in
                    sizes.merge(value) { $1 }
                }
            }
            .frame(maxHeight: onMaxHeight)
//            .background(Color.white)
//        }.glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    
    private func spacingBetween(_ current: Item, _ next: Item?) -> CGFloat {
        spacingProvider?(current, next) ?? hSpacing
    }

    private func buildRows(maxWidth: CGFloat) -> [[Item]] {
        var rows: [[Item]] = []
        var currentRow: [Item] = []
        var currentX: CGFloat = 0

        for (index, item) in items.enumerated() {
            guard let size = sizes[AnyHashable(item.id)] else {
                // If size is not yet measured, optimistically place item in current row; layout will update after measuring
                currentRow.append(item)
                continue
            }
            let nextItem: Item? = (index + 1 < items.count) ? items[index + 1] : nil
            let spacingAfter = spacingBetween(item, nextItem)

            // Wrap if doesn't fit
            if currentX > 0 && (currentX + size.width) > maxWidth {
                rows.append(currentRow)
                currentRow = []
                currentX = 0
            }

            currentRow.append(item)
            // advance cursor (spacing applies after the item)
            currentX += size.width + spacingAfter
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
//        onMaxHeight *= CGFloat(rows.count)
//        print("Это переменная высоты: \(onMaxHeight): \(rows.count): \(rows)")
        return rows
    }
}

private struct _FlowItemSizeKey2: PreferenceKey {
    static var defaultValue: [AnyHashable: CGSize] = [:]
    static func reduce(value: inout [AnyHashable: CGSize], nextValue: () -> [AnyHashable: CGSize]) { value.merge(nextValue()) { $1 } }
}

private extension Color {
    func toRGBA32() -> UInt32 {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        let ns = NSColor(self)
        let conv = ns.usingColorSpace(.deviceRGB) ?? ns
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        conv.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        let R = UInt32((r * 255).rounded())
        let G = UInt32((g * 255).rounded())
        let B = UInt32((b * 255).rounded())
        let A = UInt32((a * 255).rounded())
        return (R << 24) | (G << 16) | (B << 8) | A
    }
}
