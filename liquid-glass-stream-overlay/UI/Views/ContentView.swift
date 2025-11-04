//
//  ContentView.swift
//  liquid-glass-stream-overlay
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

import SDWebImageSwiftUI // Поддержка анимированных gif и webp (используется в EmoteImageView)

// MARK: - ContentView: основной экран приложения
// Слои:
// 1) Фон — поток с камеры или placeholder
// 2) Верхний UI (чат поверх камеры)
// 3) Glass Bar (панель с полупрозрачным материалом, маской и overlay)

struct ContentView: View {
    // MARK: - State & ViewModels
    @StateObject private var capture = CameraCaptureManager()
    @StateObject private var chat = TwitchChatManager()
    @State private var showGlassEffectBar: Bool = false

    // Прогресс анимации выреза маски: 0 — дырка размером со весь контейнер,
    // 1 — целевые размеры выреза
    @State private var cutoutAnimProgress: CGFloat = 0.0

    // Вспомогательная сборка данных бейджей (оставлено для совместимости)
    func badgeViews(_ badges: [(String, String)]) -> [BadgeViewData] {
        let badgeDataArray = badges.map { (set, version) -> BadgeViewData in
            let url = chat.allBadgeImages[set]?[version].flatMap { URL(string: $0) }
            return BadgeViewData(set: set, version: version, url: url)
        }
        return badgeDataArray
    }

    // MARK: - Body
    var body: some View {
        ZStack(alignment: .top) {
            // MARK: 1. Фон — картинка с камеры и/или placeholder
            GeometryReader { geometry in
                if let ciImage = capture.image,
                   let cgImage = capture.context.createCGImage(ciImage, from: ciImage.extent) {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: ciImage.extent.width, height: ciImage.extent.height))
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                } else if let image = NSImage(contentsOfFile: Bundle.main.path(forResource: "DRM", ofType: "png") ?? "") {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                }
            }
            .ignoresSafeArea(edges: .horizontal)

            // MARK: 2. Верхний UI — чат и т.п. (уходит вверх при показе Glass Bar)
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
//                            GlassBarLabel(chat: chat)
//                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .offset(y: showGlassEffectBar ? -geometry.size.height * 1.1 : 0)
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.1),
                    value: showGlassEffectBar
                )
            }

            // MARK: 3. Glass Bar — карточка с маской и overlay
            if showGlassEffectBar {
                GeometryReader { geometry in
                    let safeTop = geometry.safeAreaInsets.top
                    let safeSides = max(16, geometry.size.width * 0.03)
                    let _ = (safeTop, safeSides)
                    
                    HStack(alignment: .center, spacing: 16) {
                        // Левая панель с иконками (visionOS-стиль)
                        VisionSidePanel()
                            .frame(width: 72)
                            .frame(height: geometry.size.height * 0.5, alignment: .center)

                        // Карточка Glass Bar (внутри — GlassUnlockPromptView и стек сообщений)
                        GlassBarContainer(chat: chat)
                    }
                    .padding()
                    .background(
                        Rectangle()
                            .fill(.clear)
                            .glassEffect(.regular, in: .rect(cornerRadius: 0))
                    )
                    .compositingGroup()
                    // Маска с анимируемым вырезом
                    .mask(
                        GlassBarMaskShape(progress: cutoutAnimProgress)
                            .fill(.white, style: FillStyle(eoFill: true, antialiased: true))
                    )
                    // Overlay синхронизирован тем же progress
                    .overlay {
                        GlassBarCutoutOverlay(chat: chat, progress: cutoutAnimProgress)
                    }
                    // Прозрачность синхронизирована с прогрессом маски
                    .opacity(cutoutAnimProgress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .onAppear {
                        // Плавное сжатие выреза и проявление с easeInOut
                        cutoutAnimProgress = 0
                        withAnimation(.timingCurve(0.42, 0, 0.58, 1, duration: 0.4)) {
                            cutoutAnimProgress = 1
                        }
                    }
                    .onDisappear {
                        cutoutAnimProgress = 0
                    }
                }
                .zIndex(1)
            }
        }
        
        // MARK: - Toolbar
        .toolbar {
            Button(showGlassEffectBar ? "Hide Glass Bar" : "Show Glass Bar") {
                if showGlassEffectBar {
                    withAnimation(.timingCurve(0.42, 0, 0.58, 1, duration: 0.4)) {
                        cutoutAnimProgress = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showGlassEffectBar = false
                    }
                } else {
                    cutoutAnimProgress = 0
                    showGlassEffectBar = true
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
        
        // MARK: - Lifecycle
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

// MARK: - Preview
#Preview {
    ContentView()
}
