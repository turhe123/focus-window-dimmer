import SwiftUI
import AppKit

/// Launch-time wiring: registers defaults and starts the dimming engine.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        MainActor.assumeIsolated { DimmerController.shared.start() }
    }
}

/// Menu-bar-only app: a MenuBarExtra popover plus a Settings window.
@main
struct FocusWindowDimmerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(Prefs.enabled) private var enabled = true

    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(systemName: enabled ? "moon.fill" : "moon")
                .accessibilityLabel(enabled ? "Dimming on" : "Dimming off")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

/// Opens the developer's donation page.
enum Support {
    static func openDonation() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
