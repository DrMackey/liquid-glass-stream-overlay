// BadgeIconsView.swift
// Отображение значков (бейджей) отправителя

import SwiftUI

struct BadgeIconsView: View, Equatable {
    let badges: [BadgeViewData]
    let scale: CGFloat
    
    static func ==(lhs: BadgeIconsView, rhs: BadgeIconsView) -> Bool {
        lhs.badges == rhs.badges && lhs.scale == rhs.scale
    }
    
    private var badgeDisplaySize: CGFloat { 16 * scale }
    private var badgeFontSize: CGFloat { 10 * scale }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(badges, id: \.id) { badge in
                ZStack {
                    Color.clear
                    if let url = badge.url {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(width: badgeFontSize, height: badgeFontSize)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .opacity(1)
                            case .failure:
                                Text("❓")
                                    .font(.system(size: badgeFontSize))
                                    .opacity(1)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Text("❓")
                            .font(.system(size: badgeFontSize))
                            .opacity(1)
                    }
                }
                .frame(width: badgeDisplaySize, height: badgeDisplaySize)
            }
        }
    }
}
