import SwiftUI
import AppKit

/// The MenuBarExtra popover: quick controls for dimming, tint, fade and excluded apps.
struct ContentView: View {
    @ObservedObject private var dimmer = DimmerController.shared
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Prefs.enabled) private var enabled = true
    @AppStorage(Prefs.intensity) private var intensity = 0.5
    @AppStorage(Prefs.tintHex) private var tintHex = "000000"
    @AppStorage(Prefs.fadeDuration) private var fadeDuration = 0.25
    @AppStorage(Prefs.excludedApps) private var excludedRaw = ""
    @State private var showingPicker = false

    private var excluded: [String] { Prefs.excludedSet(excludedRaw) }

    private var tint: Binding<Color> {
        Binding(get: { Color(nsColor: NSColor(hex: tintHex)) },
                set: { tintHex = NSColor($0).hexString })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $enabled) {
                Text("FocusWindowDimmer").font(.headline)
            }
            .toggleStyle(.switch)

            Group {
                LabeledContent("Intensity \(Int(intensity * 100))%") {
                    Slider(value: $intensity, in: 0...0.9)
                }
                LabeledContent("Tint") {
                    ColorPicker("Tint", selection: tint, supportsOpacity: false).labelsHidden()
                }
                LabeledContent(String(format: "Fade %.2fs", fadeDuration)) {
                    Slider(value: $fadeDuration, in: 0...1.5)
                }
            }
            .disabled(!enabled)

            Divider()
            HStack {
                Text("Excluded apps").font(.subheadline.bold())
                Spacer()
                Button { showingPicker = true } label: { Image(systemName: "plus") }
                    .help("Exclude a running app")
                    .popover(isPresented: $showingPicker, arrowEdge: .trailing) {
                        RunningAppPicker(excluded: excluded) { id in
                            excludedRaw = (excluded + [id]).joined(separator: "\n")
                            showingPicker = false
                        }
                    }
            }
            if excluded.isEmpty {
                Text("No apps excluded").foregroundStyle(.secondary).font(.callout)
            } else {
                ForEach(excluded, id: \.self) { id in
                    HStack {
                        AppLabel(bundleID: id)
                        Spacer()
                        Button {
                            excludedRaw = excluded.filter { $0 != id }.joined(separator: "\n")
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
            }

            Divider()
            Button("Support / Donate ❤️") { Support.openDonation() }
            HStack {
                Button("Settings…") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 300)
    }
}

/// Shows an app's icon and name for a bundle identifier.
struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 6) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().frame(width: 16, height: 16)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
                .lineLimit(1)
        }
    }
}

/// Lists regular running apps that are not yet excluded so the user can pick one.
struct RunningAppPicker: View {
    let excluded: [String]
    let onPick: (String) -> Void

    private var apps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                && !excluded.contains($0.bundleIdentifier ?? "") }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Running apps").font(.headline).padding([.top, .horizontal])
            if apps.isEmpty {
                Text("No other apps running").foregroundStyle(.secondary).padding()
            } else {
                List(apps, id: \.processIdentifier) { app in
                    Button {
                        if let id = app.bundleIdentifier { onPick(id) }
                    } label: {
                        HStack {
                            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                            Text(app.localizedName ?? app.bundleIdentifier ?? "App")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 240, height: 300)
    }
}
