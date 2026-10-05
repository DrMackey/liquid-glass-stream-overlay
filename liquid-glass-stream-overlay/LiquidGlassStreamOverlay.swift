import SwiftUI
import AppKit

/// Делегат приложения. Все методы `NSApplicationDelegate` необязательные,
/// поэтому пустой класс полностью допустим и сохраняет место для будущей
/// настройки после запуска.
///
/// Метод `applicationDidFinishLaunching(_:)` здесь намеренно не объявляется:
/// в текущем SDK он не сопоставляется ни с одной комбинацией аннотаций
/// (`@MainActor`, `nonisolated`, `@objc` — последнее вообще не компилируется
/// для параметра `Notification`) и даёт предупреждение «nearly matches optional
/// requirement». Объявлять его вручную не имеет смысла: пустой метод ничего
/// не делал.
class AppDelegate: NSObject, NSApplicationDelegate {}

@main
struct NewTestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1920, idealWidth: 1920, maxWidth: 1920,
                                       minHeight: 1080, idealHeight: 1080, maxHeight: 1080)
        }
        .defaultSize(width: 1920, height: 1080)
        Settings {}
    }
}
