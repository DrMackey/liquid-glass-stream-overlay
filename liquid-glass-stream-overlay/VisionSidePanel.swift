// VisionSidePanel.swift
// Левая декоративная панель в стиле visionOS

import SwiftUI

struct VisionSidePanel: View {
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
                    .overlay(
                        Image(systemName: symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                    )
                    .frame(width: 48, height: 48)
                    .background(
                        Group {
                            if idx == 0 {
                                Color.clear
                                    .glassEffect(.regular, in: .circle)
                            } else {
                                Color.clear
                            }
                        }
                    )
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
            RoundedRectangle(cornerRadius: 100, style: .continuous)
                .fill(Color.clear)
                .background(Color.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 30))
        )
        .shadow(radius: 10)
    }
}

