// NotificationBannerView.swift
// Обёртка для баннера уведомлений с типовой анимацией

import SwiftUI

struct NotificationBannerView<Content: View>: View {
    let content: () -> Content
    var body: some View {
        content()
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 20.0))
    }
}
