import SwiftUI
import AppKit
import ServiceManagement

/// Settings window: hotkey, schedule, menu bar dimming, launch at login and Accessibility.
struct SettingsView: View {
    @ObservedObject private var dimmer = DimmerController.shared
    @AppStorage(Prefs.includeMenuBar) private var includeMenuBar = false
    @AppStorage(Prefs.scheduleEnabled) private var scheduleEnabled = false
    @AppStorage(Prefs.scheduleStart) private var scheduleStart = 9 * 60
    @AppStorage(Prefs.scheduleEnd) private var scheduleEnd = 18 * 60
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Hotkey") {
                LabeledContent("Toggle dimming") { HotKeyRecorder() }
            }
            Section("Schedule") {
                Toggle("Only dim between chosen hours", isOn: $scheduleEnabled)
                DatePicker("Start", selection: timeBinding($scheduleStart), displayedComponents: .hourAndMinute)
                    .disabled(!scheduleEnabled)
                DatePicker("End", selection: timeBinding($scheduleEnd), displayedComponents: .hourAndMinute)
                    .disabled(!scheduleEnabled)
            }
            Section("General") {
                Toggle("Also dim the menu bar", isOn: $includeMenuBar)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Accessibility") {
                if dimmer.accessibilityTrusted {
                    Label("Accessibility enabled — window changes are tracked instantly.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Optional. Dimming works without it, but granting Accessibility makes it react instantly when you switch or drag windows. If the prompt doesn't appear, open System Settings › Privacy & Security › Accessibility and enable FocusWindowDimmer.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Grant Accessibility…") { dimmer.requestAccessibility() }
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
            Section {
                Button("Support / Donate ❤️") { Support.openDonation() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    /// Bridges a minutes-after-midnight Int to a Date for DatePicker.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60,
                                         second: 0, of: Date()) ?? Date() },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Click-to-record control that captures the next key combination as the global hotkey.
struct HotKeyRecorder: View {
    @AppStorage(Prefs.hotKeyLabel) private var label = "⌥⌘D"
    @AppStorage(Prefs.hotKeyCode) private var keyCode = 2
    @AppStorage(Prefs.hotKeyModifiers) private var modifiers = 0
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press keys… (Esc cancels)" : label) {
            recording ? stop() : start()
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Escape
            let mods = HotKeyManager.carbonModifiers(event.modifierFlags)
            guard mods != 0 else { NSSound.beep(); return nil } // require at least one modifier
            keyCode = Int(event.keyCode)
            modifiers = mods
            label = HotKeyManager.label(for: event)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        DimmerController.shared.registerHotKey()
    }
}
