//
//  ContentView.swift
//  New Test App
//
//  Created by Rodney Mackey on 09.08.2025.
//

import SwiftUI
import AVFoundation
import Combine
import Foundation
import Network

#if os(macOS)
import AppKit
#endif

import SDWebImageSwiftUI // Добавлено для поддержки анимированных gif и webp


struct ContentView: View {
    @StateObject private var capture = CameraCaptureManager()
    @StateObject private var chat = TwitchChatManager()
    @State private var showGlassEffectBar: Bool = false

    func badgeViews(_ badges: [(String, String)]) -> [BadgeViewData] {
        let badgeDataArray = badges.map { (set, version) -> BadgeViewData in
            let url = chat.allBadgeImages[set]?[version].flatMap { URL(string: $0) }
            return BadgeViewData(set: set, version: version, url: url)
        }
        return badgeDataArray
    }

    var body: some View {
        ZStack(alignment: .top) {

            // 1. Слой фона — картинка с камеры и/или placeholder
            GeometryReader { geometry in
                if let ciImage = capture.image,
                   let cgImage = capture.context.createCGImage(ciImage, from: ciImage.extent) {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: ciImage.extent.width, height: ciImage.extent.height))
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: .infinity, alignment: .top)
                } else if let image = NSImage(contentsOfFile: Bundle.main.path(forResource: "DRM", ofType: "png") ?? "") {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: .infinity, alignment: .top)
                }
            }
            .ignoresSafeArea(edges: .horizontal) // фон может уходить под края по горизонтали

            // 2. Слой UI (чат и т.д.) — основной верхний контент (не Glass Bar)
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        VStack {
                            if let message = chat.lastMessage {
                                let maxMessageWidth = geometry.size.width * 0.6
                                let displayMessage = chat.makeDisplayMessage(message, maxWidth: maxMessageWidth, badgeUrlMap: chat.allBadgeImages)
                                
                                MessageTextView(
                                    badges: displayMessage.badges,
                                    sender: displayMessage.sender,
                                    senderColor: displayMessage.senderColor,
                                    parts: displayMessage.visibleParts,
                                    maxWidth: maxMessageWidth,
                                    badgeViews: { _ in displayMessage.badges },
                                    isTruncated: displayMessage.isTruncated
                                )
                                .bold()
                                .font(.title)
                                .padding(.top, 12)
                            }
                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .offset(y: showGlassEffectBar ? -500 : 0)
                .opacity(showGlassEffectBar ? 0 : 1)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showGlassEffectBar)
            }

            // 3. Glass Bar (карточка с двумя секциями: верх — чат, низ — вырез)
            if showGlassEffectBar {
                GeometryReader { geometry in
                    let safeTop = geometry.safeAreaInsets.top
                    let safeSides = max(16, geometry.size.width * 0.03)
                    let _ = (safeTop, safeSides)
                    
                    HStack(alignment: .center, spacing: 16) {
                        // Левая вертикальная панель в стиле visionOS (декоративные кнопки)
                        VisionSidePanel()
                            .frame(width: 72)
                            .frame(height: geometry.size.height * 0.5, alignment: .center)

                        // Карточка Glass Bar
                        GlassBarContainer(chat: chat)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .toolbar {
            Button(showGlassEffectBar ? "Hide Glass Bar" : "Show Glass Bar") {
                withAnimation {
                    showGlassEffectBar.toggle()
                }
            }
            if let errorMsg = capture.errorMessage {
                Text(errorMsg)
                    .foregroundColor(.red)
                    .padding(.trailing, 8)
            }
            Picker("Select Camera:", selection: $capture.selectedDeviceID) {
                ForEach(capture.availableDevices, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(device.uniqueID as String?)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: capture.selectedDeviceID) { _ in
                capture.startSession()
            }
            Button("Start Camera") {
                guard !capture.availableDevices.isEmpty else { return }
                if let facetime = capture.availableDevices.first(where: { $0.localizedName.contains("FaceTime") || $0.localizedName.contains("Integrated") }) {
                    capture.selectedDeviceID = facetime.uniqueID
                } else if let first = capture.availableDevices.first {
                    capture.selectedDeviceID = first.uniqueID
                }
            }
            Button("Stop Camera") {
                capture.stopSession()
            }
        }
        .toolbar(removing: .title)
        .onAppear {
            capture.updateAvailableDevices()
            capture.startSession()
            chat.start()
            Task {
                await chat.loadAllBadges(channelLogin: TWITCH_CHANNEL)
                await chat.loadGlobalEmotes()
                if let msg = chat.lastMessage {
                    let badgeViewData = chat.badgeViews(from: msg.badges, badgeUrlMap: chat.allBadgeImages)
                    chat.lastMessage = TwitchChatManager.Message(
                        sender: msg.sender,
                        text: msg.text,
                        badges: msg.badges,
                        senderColor: msg.senderColor,
                        badgeViewData: badgeViewData
                    )
                }
            }
        }
    }
}

// Левая вертикальная панель (visionOS-стиль), чисто декоративная
private struct VisionSidePanel: View {
    #if os(macOS)
    @State private var hoverIndex: Int? = nil
    #endif

    private let icons: [String] = [
        "bolt.fill", "gamecontroller.fill", "message.fill",
        "mic.fill", "sparkles", "person.2.fill"
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(icons.indices, id: \.self) { idx in
                let symbol = icons[idx]
                Circle()
                    .fill(Color.clear)
                    .background(Color.clear)
                    .glassEffect(.regular, in: .circle)
                    .overlay(
                        Image(systemName: symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
                    #if os(macOS)
                    .onHover { isHover in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            hoverIndex = isHover ? idx : nil
                        }
                    }
                    .scaleEffect(hoverIndex == idx ? 1.06 : 1.0)
                    .opacity(hoverIndex == idx ? 1.0 : 0.92)
                    #endif
            }
        }
        .padding(12)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 72, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.clear)
                .background(Color.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 30))
        )
        .shadow(radius: 10)
    }
}

// Контейнер карточки Glass Bar: единый материал + сквозной вырез в нижней половине
private struct GlassBarContainer: View {
    @ObservedObject var chat: TwitchChatManager

    var body: some View {
        GeometryReader { containerGeo in
            ZStack {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.clear)
                    .background(Color.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 30))
                
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        VStack {
                            GlassUnlockPromptView()
                                .frame(maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        Divider()
                            .frame(maxHeight: .infinity)
                        
                        VStack {
                            GlassBarLabel(chat: chat)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.clear)
                            .background(Color.clear)
                            .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    }
                }
                .padding(16)
            }
            .compositingGroup()
            .mask(
                GeometryReader { geo in
                    let size = geo.size
                    let rect = CGRect(origin: .zero, size: size)

                    let inset: CGFloat = 17
                    let cutoutCorner: CGFloat = 20
                    let outerCorner: CGFloat = 30
                    let lowerHeight = size.height / 2.0

                    let oldY = lowerHeight + inset
                    let oldHeight = max(0, lowerHeight - inset * 2)
                    let bottomY = oldY + oldHeight

                    let newY = max(0, oldY - 8)
                    let newHeight = max(0, bottomY - newY)

                    let cutoutRect = CGRect(
                        x: inset,
                        y: newY,
                        width: max(0, size.width - inset * 2),
                        height: newHeight
                    )

                    Canvas { context, _ in
                        var path = Path()
                        let outerPath = RoundedRectangle(cornerRadius: outerCorner, style: .continuous).path(in: rect)
                        path.addPath(outerPath)
                        let cutoutPath = RoundedRectangle(cornerRadius: cutoutCorner, style: .continuous).path(in: cutoutRect)
                        path.addPath(cutoutPath)
                        context.fill(path, with: .color(.white), style: FillStyle(eoFill: true, antialiased: true))
                    }
                }
            )
            // Overlay: постер + два текстовых блока; фон — только по контенту; текст прижат к низу постера
            .overlay {
                GeometryReader { geo in
                    let size = geo.size
                    let inset: CGFloat = 17
                    let lowerHeight = size.height / 2.0
                    let oldY = lowerHeight + inset
                    let oldHeight = max(0, lowerHeight - inset * 2)
                    let bottomY = oldY + oldHeight
                    let newY = max(0, oldY - 8)
                    let newHeight = max(0, bottomY - newY)
                    let cutoutRect = CGRect(
                        x: inset,
                        y: newY,
                        width: max(0, size.width - inset * 2),
                        height: newHeight
                    )

                    // Параметры лэйаута
                    let padding: CGFloat = 16
                    let maxW = max(0, cutoutRect.width - padding * 2)
                    let maxH = max(0, cutoutRect.height - padding * 2)

                    // Постер 2:3, уменьшенный в 2 раза
                    let rawPosterWidth = min(220, maxW * 0.28)
                    let rawPosterHeight = rawPosterWidth * 1.5
                    let scale = min(1.0, rawPosterHeight == 0 ? 1.0 : (maxH / rawPosterHeight))
                    let posterScale: CGFloat = 0.5
                    let posterWidth = rawPosterWidth * scale * posterScale
                    let posterHeight = rawPosterHeight * scale * posterScale

                    let spacing: CGFloat = 12
                    let maxTextWidth = max(0, maxW - posterWidth - spacing)
                    let glassRadius: CGFloat = 14

                    ZStack(alignment: .bottomLeading) {
                        HStack(alignment: .bottom, spacing: spacing) {
                            // Блок постера: реальное изображение категории (или заглушка)
                            ZStack {
                                if let url = chat.categoryImageURL {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .empty:
                                            ProgressView()
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        case .failure:
                                            Image(systemName: "photo")
                                                .resizable()
                                                .scaledToFit()
                                                .foregroundStyle(.white.opacity(0.8))
                                                .padding(24)
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                } else {
                                    Image(systemName: "photo")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundStyle(.white.opacity(0.8))
                                        .padding(24)
                                }
                            }
                            .frame(width: posterWidth, height: posterHeight)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)

                            // Два текстовых блока: фон строго по контенту (fixedSize + glassEffect ДО frame)
                            VStack(alignment: .leading, spacing: 8) {
                                // Название трансляции
                                Text(chat.streamTitle.isEmpty ? "Название трансляции" : chat.streamTitle)
                                    .font(.system(size: 18, weight: .semibold))
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .multilineTextAlignment(.leading)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .fixedSize(horizontal: true, vertical: true) // контентная ширина
                                    .glassEffect(.regular, in: .rect(cornerRadius: glassRadius))
                                    .frame(maxWidth: maxTextWidth, alignment: .leading) // ограничиваем максимум

                                // Категория стриминга
                                Text(chat.categoryName.isEmpty ? "Категория" : chat.categoryName)
                                    .font(.system(size: 14, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundStyle(.white.opacity(0.95))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .fixedSize(horizontal: true, vertical: true)
                                    .glassEffect(.regular, in: .rect(cornerRadius: glassRadius))
                                    .frame(maxWidth: maxTextWidth, alignment: .leading)
                            }
                        }
                        .padding(.leading, padding)
                        .padding(.bottom, padding)
                    }
                    .frame(width: cutoutRect.width, height: cutoutRect.height, alignment: .bottomLeading)
                    .offset(x: cutoutRect.minX, y: cutoutRect.minY)
                    .allowsHitTesting(false)
                }
            }
            .shadow(radius: 10)
        }
    }
}

// Левый стеклянный блок с подсказкой "разблокируйте Вебкамеру"
private struct GlassUnlockPromptView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.clear)
                .background(Color.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))

            Text("разблокируйте Вебкамеру")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
        }
    }
}

// Если нужен path для других сценариев
private struct CutoutShapeInSection: Shape {
    let cutoutRect: CGRect
    let cutoutCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addPath(Path(rect))
        let inner = RoundedRectangle(cornerRadius: cutoutCornerRadius, style: .continuous).path(in: cutoutRect)
        path.addPath(inner)
        return path
    }
}

struct GlassBarLabel: View {
    @ObservedObject var chat: TwitchChatManager
    
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
                let partWidth: CGFloat = 32
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
                let partWidth: CGFloat = 32
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
        VStack(alignment: .leading, spacing: 8) {
            if chat.messages.isEmpty {
                Text("Нет сообщений.")
                    .foregroundColor(.gray)
            } else {
                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            let recentMessages = Array(chat.messages.suffix(10).reversed())
                            
                            ForEach(recentMessages, id: \.id) { msg in
                                let displayMessage = chat.makeDisplayMessage(msg, maxWidth: geometry.size.width * 1000, badgeUrlMap: chat.allBadgeImages)
                                
                                #if os(macOS)
                                let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                                #else
                                let font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
                                #endif
                                
                                #if os(macOS)
                                let nicknameWidth = displayMessage.sender.size(withAttributes: [.font: font]).width + font.pointSize * 0.3
                                #else
                                let nicknameWidth = (displayMessage.sender as NSString).size(withAttributes: [.font: font]).width + font.pointSize * 0.3
                                #endif
                                let badgesTotalWidth = CGFloat(displayMessage.badges.count) * 18 + CGFloat(max(displayMessage.badges.count-1,0)) * 2
                                
                                let wrappedLines = wrapMessageParts(displayMessage.visibleParts, font: font, maxWidth: geometry.size.width * 0.7, firstLinePrefixWidth: nicknameWidth + badgesTotalWidth + 8)
                                
                                NotificationBannerView {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(alignment: .top, spacing: 8) {
                                            BadgeIconsView(badges: displayMessage.badges)
                                            Text(displayMessage.sender)
                                                .bold()
                                                .foregroundColor(displayMessage.senderColor)
                                            if let firstLine = wrappedLines.first {
                                                ForEach(firstLine.indices, id: \.self) { i in
                                                    let part = firstLine[i]
                                                    switch part {
                                                    case .text(let string):
                                                        Text(string + " ").foregroundColor(.primary)
                                                    case .emote(_, let urlStr, let animated):
                                                        if let url = URL(string: urlStr) {
                                                            EmoteImageView(url: url, size: 24, animated: animated)
                                                        }
                                                    }
                                                }
                                            }
                                            Spacer()
                                        }
                                        ForEach(wrappedLines.indices.dropFirst(), id: \.self) { lineIndex in
                                            HStack(spacing: 2) {
                                                let line = wrappedLines[lineIndex]
                                                ForEach(line.indices, id: \.self) { i in
                                                    let part = line[i]
                                                    switch part {
                                                    case .text(let string):
                                                        Text(string + " ").foregroundColor(.primary)
                                                    case .emote(_, let urlStr, let animated):
                                                        if let url = URL(string: urlStr) {
                                                            EmoteImageView(url: url, size: 24, animated: animated)
                                                        }
                                                    }
                                                }
                                                if lineIndex == wrappedLines.indices.last && displayMessage.isTruncated {
                                                    Text("…")
                                                }
                                            }
                                        }
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.bottom, 6)
                            }
                        }
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: chat.messages)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BadgeIconsView: View, Equatable {
    let badges: [BadgeViewData]
    static func ==(lhs: BadgeIconsView, rhs: BadgeIconsView) -> Bool {
        lhs.badges == rhs.badges
    }
    var body: some View {
        HStack(spacing: 2) {
            ForEach(badges, id: \.id) { badge in
                if let url = badge.url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().frame(width: 18, height: 18)
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18)
                        case .failure:
                            Text("❓").frame(width: 18, height: 18)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Text("❓").frame(width: 18, height: 18)
                }
            }
        }
    }
}

struct NotificationBannerView<Content: View>: View {
    let content: () -> Content
    var body: some View {
        content()
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 20.0))
    }
}

#Preview {
    ContentView()
}

