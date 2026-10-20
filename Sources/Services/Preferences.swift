import AppKit
import Carbon.HIToolbox

/// Central list of UserDefaults keys and defaults shared by `@AppStorage` views and the dimmer engine.
enum Prefs {
    static let enabled = "enabled"
    static let intensity = "intensity"            // 0.0 ... 0.9
    static let tintHex = "tintHex"                // "RRGGBB"
    static let fadeDuration = "fadeDuration"      // seconds
    static let includeMenuBar = "includeMenuBar"
    static let excludedApps = "excludedApps"      // newline-separated bundle identifiers
    static let scheduleEnabled = "scheduleEnabled"
    static let scheduleStart = "scheduleStart"    // minutes after midnight
    static let scheduleEnd = "scheduleEnd"
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
    static let hotKeyLabel = "hotKeyLabel"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            enabled: true,
            intensity: 0.5,
            tintHex: "000000",
            fadeDuration: 0.25,
            includeMenuBar: false,
            excludedApps: "",
            scheduleEnabled: false,
            scheduleStart: 9 * 60,
            scheduleEnd: 18 * 60,
            hotKeyCode: kVK_ANSI_D,
            hotKeyModifiers: cmdKey | optionKey,
            hotKeyLabel: "⌥⌘D",
        ])
    }

    /// Decodes the stored newline-separated exclusion list.
    static func excludedSet(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Whether `now` falls within the start...end window (supports ranges that wrap past midnight).
    static func isWithinSchedule(start: Int, end: Int, now: Date = Date()) -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if start == end { return true }
        return start < end ? (m >= start && m < end) : (m >= start || m < end)
    }
}

extension NSColor {
    /// Creates a colour from a "RRGGBB" string, falling back to black on malformed input.
    convenience init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// "RRGGBB" representation in sRGB.
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "000000" }
        return String(format: "%02X%02X%02X", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
