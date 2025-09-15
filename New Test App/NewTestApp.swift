import SwiftUI
#if os(macOS)
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Additional setup after launch can go here
    }
}
#endif

@main
struct NewTestApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
//        .defaultSize(width: 1920, height: 1080)
        Settings {}
    }
}
