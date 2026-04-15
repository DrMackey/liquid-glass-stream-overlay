import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Additional setup after launch can go here
    }
}

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
