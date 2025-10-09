// GlassBarCutoutOverlay.swift
// Overlay для выреза с постером и текстами, синхронизирован с маской

import SwiftUI

struct GlassBarCutoutOverlay: View {
    @ObservedObject var chat: TwitchChatManager
    let progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let inset: CGFloat = 17
            let parentPadding: CGFloat = 16

            let contentRect = CGRect(origin: .zero, size: size).insetBy(dx: parentPadding, dy: parentPadding)
            let contentSize = contentRect.size

            let lowerHeight = contentSize.height / 2.0
            let oldYLocal = lowerHeight + inset
            let oldHeight = max(0, lowerHeight - inset * 2)
            let bottomYLocal = oldYLocal + oldHeight
            let newYLocal = max(0, oldYLocal - 8)
            let newHeight = max(0, bottomYLocal - newYLocal)

            let leftPanelWidth: CGFloat = 72
            let hSpacing: CGFloat = 16

            let targetCutoutRectLocal = CGRect(
                x: leftPanelWidth + hSpacing + inset,
                y: newYLocal,
                width: max(0, contentSize.width - (leftPanelWidth + hSpacing) - inset * 2),
                height: newHeight
            )
            let targetCutoutRect = targetCutoutRectLocal.offsetBy(dx: contentRect.minX, dy: contentRect.minY)

            let startCutoutRect = contentRect

            let t = max(0, min(1, progress))
            let easedT = easeInOut(t)
            
            let animatedCutoutRect = CGRect(
                x: lerp(startCutoutRect.minX, targetCutoutRect.minX, t: easedT),
                y: lerp(startCutoutRect.minY, targetCutoutRect.minY, t: easedT),
                width: lerp(startCutoutRect.width, targetCutoutRect.width, t: easedT),
                height: lerp(startCutoutRect.height, targetCutoutRect.height, t: easedT)
            )

            let padding: CGFloat = 16
            let maxW = max(0, animatedCutoutRect.width - padding * 2)
            let maxH = max(0, animatedCutoutRect.height - padding * 2)

            let rawPosterWidth = min(220, maxW * 0.28)
            let rawPosterHeight = rawPosterWidth * 1.5
            let scale = min(1.0, rawPosterHeight == 0 ? 1.0 : (maxH / rawPosterHeight))
            let posterScale: CGFloat = 0.8
            let posterWidth = rawPosterWidth * scale * posterScale
            let posterHeight = rawPosterHeight * scale * posterScale

            let spacing: CGFloat = 12
            let maxTextWidth = max(0, maxW - posterWidth - spacing)
            let glassRadius: CGFloat = 14

            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: spacing) {
                    ZStack {
                        if let url = chat.categoryImageURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: posterWidth, height: posterHeight)
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                            .blendMode(.overlay)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(chat.streamTitle.isEmpty ? "Название трансляции" : chat.streamTitle)
                            .font(.system(size: 28, weight: .semibold))
                            .lineLimit(3) // allow up to 3 lines to wrap within the cutout
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .glassEffect(.regular, in: .rect(cornerRadius: glassRadius))
                            .frame(maxWidth: maxTextWidth, alignment: .leading)

                        Text(chat.categoryName.isEmpty ? "Категория" : chat.categoryName)
                            .font(.system(size: 24, weight: .medium))
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
            .frame(width: animatedCutoutRect.width, height: animatedCutoutRect.height, alignment: .bottomLeading)
            .offset(x: animatedCutoutRect.minX, y: animatedCutoutRect.minY)
            .allowsHitTesting(false)
        }
    }
}
