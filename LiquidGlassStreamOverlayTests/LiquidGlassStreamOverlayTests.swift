//
//  LiquidGlassStreamOverlayTests.swift
//  LiquidGlassStreamOverlayTests
//

import Testing
import Foundation
import SwiftUI
@testable import Liquid_Glass_Stream_Overlay

struct LiquidGlassStreamOverlayTests {

    @Test func targetIsConfiguredForSwiftTesting() {
        #expect(Bool(true))
    }

}

@Suite("Локальные уведомления")
struct LocalNotificationTests {

    @Test("Telegram-уведомление: содержимое задано, звук отключён")
    func telegramDefinition() {
        let telegram = LocalNotifications.telegram
        #expect(telegram.title == "Подписывайся на Telegram")
        #expect(telegram.body == "Уведомления о стримах и новостях")
        #expect(telegram.icon == "Telegram")
        #expect(telegram.playsSound == false)
    }

    @Test("Обычное уведомление по умолчанию проигрывает звук")
    func defaultNotificationPlaysSound() {
        let notification = Notification(
            id: UUID(),
            kind: .follow,
            title: "Заголовок",
            body: "Текст",
            sender: "eventsub",
            senderColor: .gray
        )
        #expect(notification.playsSound == true)
    }
}
