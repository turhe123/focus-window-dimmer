import AppKit
import ApplicationServices
import CoreGraphics
import Combine

/// Borderless, click-through window that paints the dimming colour over one screen region.
final class OverlayWindow: NSWindow {
    init(frame: NSRect, level: NSWindow.Level) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        alphaValue = 0
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the overlay windows and keeps them ordered directly below the frontmost app's top window.
/// Listens to app activation, Space/screen changes, Accessibility window events and a 5 Hz safety timer.
@MainActor
final class DimmerController: ObservableObject {
    static let shared = DimmerController()

    @Published private(set) var isDimming = false
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()

    private var overlays: [OverlayWindow] = []
    private var menuBarStrips: [OverlayWindow] = []
    private var lastFrontWindow: CGWindowID = 0
    private var currentAlpha: CGFloat = -1
    private var axObserver: AXObserver?
    private var observedPID: pid_t = 0
    private var moveUpdatePending = false
    private var timers: [Timer] = []
    private var cancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    private init() {}

    /// Builds overlays, wires observers and timers. Call once at launch.
    func start() {
        rebuildOverlays()
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.attachAXObserver(); self?.update() }
        }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildOverlays() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildOverlays() }
        }
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.preferencesChanged() }
            .store(in: &cancellables)

        timers.append(Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })

        HotKeyManager.shared.onPress = { [weak self] in
            MainActor.assumeIsolated { self?.toggleEnabled() }
        }
        registerHotKey()
        attachAXObserver()
        update()
    }

    func toggleEnabled() {
        defaults.set(!defaults.bool(forKey: Prefs.enabled), forKey: Prefs.enabled)
    }

    func registerHotKey() {
        HotKeyManager.shared.register(keyCode: defaults.integer(forKey: Prefs.hotKeyCode),
                                      modifiers: defaults.integer(forKey: Prefs.hotKeyModifiers))
    }

    /// Prompts for Accessibility only when the user asks for it.
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        accessibilityTrusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if accessibilityTrusted { attachAXObserver() }
    }

    private func preferencesChanged() {
        let color = NSColor(hex: defaults.string(forKey: Prefs.tintHex) ?? "000000")
        (overlays + menuBarStrips).forEach { $0.backgroundColor = color }
        if !accessibilityTrusted, AXIsProcessTrusted() { accessibilityTrusted = true; attachAXObserver() }
        registerHotKey()
        currentAlpha = -1
        update()
    }

    // MARK: Overlay lifecycle

    /// Recreates one overlay (and optional menu bar strip) per screen; used on launch, hot plug and Space changes.
    func rebuildOverlays() {
        (overlays + menuBarStrips).forEach { $0.orderOut(nil); $0.close() }
        overlays.removeAll(); menuBarStrips.removeAll()
        let color = NSColor(hex: defaults.string(forKey: Prefs.tintHex) ?? "000000")
        for screen in NSScreen.screens {
            let overlay = OverlayWindow(frame: screen.frame, level: .normal)
            overlay.backgroundColor = color
            overlays.append(overlay)

            let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 0)
            if barHeight > 0 {
                let rect = NSRect(x: screen.frame.minX, y: screen.frame.maxY - barHeight,
                                  width: screen.frame.width, height: barHeight)
                let strip = OverlayWindow(frame: rect, level: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1))
                strip.backgroundColor = color
                menuBarStrips.append(strip)
            }
        }
        lastFrontWindow = 0
        currentAlpha = -1
        update()
    }

    // MARK: Core update

    /// Computes the desired alpha and keeps the overlays ordered beneath the front window.
    func update() {
        let enabled = defaults.bool(forKey: Prefs.enabled)
        let inSchedule = !defaults.bool(forKey: Prefs.scheduleEnabled) || Prefs.isWithinSchedule(
            start: defaults.integer(forKey: Prefs.scheduleStart), end: defaults.integer(forKey: Prefs.scheduleEnd))
        let front = NSWorkspace.shared.frontmostApplication
        let excluded = Prefs.excludedSet(defaults.string(forKey: Prefs.excludedApps) ?? "")
        let isExcluded = front?.bundleIdentifier.map { excluded.contains($0) } ?? false
        let windowID = front.flatMap { topWindow(of: $0.processIdentifier) }
        // Our own menu bar popover has no normal-layer window: keep the current state instead of fading out.
        if front?.processIdentifier == ProcessInfo.processInfo.processIdentifier, windowID == nil, enabled { return }

        let active = enabled && inSchedule && !isExcluded && windowID != nil
        let target: CGFloat = active ? CGFloat(min(max(defaults.double(forKey: Prefs.intensity), 0), 0.9)) : 0
        let stripTarget: CGFloat = defaults.bool(forKey: Prefs.includeMenuBar) ? target : 0

        if let windowID, active, windowID != lastFrontWindow {
            overlays.forEach { $0.order(.below, relativeTo: Int(windowID)) }
            lastFrontWindow = windowID
        }
        if active { menuBarStrips.forEach { $0.orderFrontRegardless() } }
        if target != currentAlpha {
            animate(to: target, stripAlpha: stripTarget)
        }
        isDimming = active && target > 0
    }

    private func animate(to alpha: CGFloat, stripAlpha: CGFloat) {
        currentAlpha = alpha
        let duration = max(defaults.double(forKey: Prefs.fadeDuration), 0)
        if alpha > 0 { overlays.forEach { if !$0.isVisible { $0.orderFrontRegardless(); $0.alphaValue = 0 } } }
        if alpha > 0, lastFrontWindow != 0 { overlays.forEach { $0.order(.below, relativeTo: Int(lastFrontWindow)) } }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            overlays.forEach { $0.animator().alphaValue = alpha }
            menuBarStrips.forEach { $0.animator().alphaValue = stripAlpha }
        }
    }

    /// Finds the topmost normal-layer window owned by `pid` using the public window list (no permission needed).
    private func topWindow(of pid: pid_t) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let ours = Set((overlays + menuBarStrips).map { CGWindowID($0.windowNumber) })
        for info in list {
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID, !ours.contains(number) else { continue }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            if alpha > 0, (bounds["Width"] ?? 0) > 40, (bounds["Height"] ?? 0) > 40 { return number }
        }
        return nil
    }

    // MARK: Accessibility observer

    /// Subscribes to focus/move events of the frontmost app for instant re-ordering (only if trusted).
    private func attachAXObserver() {
        guard AXIsProcessTrusted(), let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != observedPID else { return }
        if let old = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .defaultMode)
        }
        axObserver = nil
        observedPID = pid
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let controller = Unmanaged<DimmerController>.fromOpaque(refcon).takeUnretainedValue()
            let moved = (notification as String) == kAXWindowMovedNotification
            MainActor.assumeIsolated { moved ? controller.scheduleThrottledUpdate() : controller.forceReorder() }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                     kAXWindowCreatedNotification, kAXWindowMovedNotification, kAXWindowMiniaturizedNotification] {
            AXObserverAddNotification(observer, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = observer
    }

    private func forceReorder() {
        lastFrontWindow = 0
        update()
    }

    /// Coalesces bursts of window-moved events into at most ~20 updates per second.
    private func scheduleThrottledUpdate() {
        guard !moveUpdatePending else { return }
        moveUpdatePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.moveUpdatePending = false; self?.forceReorder() }
        }
    }
}
