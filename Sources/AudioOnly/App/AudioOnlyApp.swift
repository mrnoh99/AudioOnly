import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run`으로 실행해도 Dock/메뉴바가 있는 일반 앱으로 동작하도록 한다.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProcessRegistry.shared.terminateAll()
    }
}

@main
struct AudioOnlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings()
    @StateObject private var tools = ToolManager()
    @StateObject private var queue = JobQueue()

    var body: some Scene {
        WindowGroup("AudioOnly") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(tools)
                .environmentObject(queue)
                .frame(minWidth: 780, minHeight: 640)
                .task { await tools.refresh(settings: settings) }
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(tools)
        }
    }
}
