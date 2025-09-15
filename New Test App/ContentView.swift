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
        ZStack(alignment: .bottom) {
            // 1. Слой фона — картинка с камеры и/или placeholder
            GeometryReader { geometry in
                if let ciImage = capture.image,
                   let cgImage = capture.context.createCGImage(ciImage, from: ciImage.extent) {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: ciImage.extent.width, height: ciImage.extent.height))
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .frame(maxWidth: geometry.size.width, maxHeight: .infinity)
                } else if let image = NSImage(contentsOfFile: Bundle.main.path(forResource: "DRM", ofType: "png") ?? "") {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .frame(maxWidth: geometry.size.width, maxHeight: .infinity)
                }
            }
            // 2. Слой UI (чат и т.д.)
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
            // 3. Glass Bar
            if showGlassEffectBar {
                VStack {
                    Spacer()
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 30.0)
//                            .fill(.ultraThinMaterial)
                            .shadow(radius: 10)
                            .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.8)
                            .overlay(
                                GlassBarLabel(chat: chat)
                            )
                            .glassEffect(.clear, in: .rect(cornerRadius: 30.0))
                            .padding(.horizontal, 40)
                            .padding(.bottom, 40)
                            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.5) // Центрируем ближе к низу
                    }
//                    .frame(height: 300) // Ограничиваем высоту GeometryReader
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
    //    .onDisappear {
    //        chat.stop()
    //    }
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
                // Разбиваем строку на слова, включая пробелы
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
                // Разбиваем строку на слова, включая пробелы
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
                        .frame(maxWidth: geometry.size.width * 0.96, alignment: .leading)
                    }
                }
            }
        }
        .padding()
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
//            .padding(.horizontal, 20)
//            .padding(.vertical, 16)
//            .padding(.top, 4)
//            .padding(.horizontal, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 20.0))
            
    }
}

#Preview {
    ContentView()
    
}

