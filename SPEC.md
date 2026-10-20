# FocusWindowDimmer — specification

**Tagline:** Dim everything behind the active window so your eyes and attention stay on the one thing you are working on.

**Category:** Focus & Productivity

**Inspired by (paid):** HazeOver ($4.99 one-time)

**Frameworks:** SwiftUI, AppKit, CoreGraphics, ApplicationServices, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: HazeOver is a Mac App Store focus app priced around 4.99 dollars one-time that darkens all windows except the frontmost one, with a very high rating and frequent mentions in lists of apps for ADHD and distraction free work. Our free clean-room version delivers the same dimming overlay with a few adjustments.

Feature set: A dimming layer is placed behind the active window and above all other windows on every display. Controls include dim intensity from zero to ninety percent, an optional tint color, fade animation duration, an option to also dim the desktop and menu bar, an option to keep dimming off for chosen apps, and a hotkey to toggle on and off. A schedule option can enable dimming only between chosen hours. The menu bar icon shows the on or off state.

UI spec: MenuBarExtra with a half moon symbol. The popover has an enabled toggle, an intensity slider, a tint color well, a fade duration slider, and a list of excluded apps with an add button that opens a running apps picker. Settings has the hotkey recorder, schedule start and end times, include menu bar toggle, and launch at login. When disabled, the slider is greyed out. Empty state for exclusions says no apps excluded.

Technical approach: For each NSScreen create a borderless transparent NSWindow filled with a black view at the chosen alpha, ignoring mouse events, with canJoinAllSpaces and fullScreenAuxiliary collection behavior. The trick is ordering: use the window's order relative to the front window with orderWindow below, passing the window number of the frontmost app's main window. Find that number using CGWindowListCopyWindowInfo filtered to the frontmost application's process id and layer zero, choosing the topmost entry. Observe NSWorkspace didActivateApplicationNotification for app switches, and use an AXObserver for focused window changed and window moved events to re-order. A repeating timer at five hertz acts as a safety net. Animate alpha with NSAnimationContext. Preferences are in AppStorage, schedule is evaluated by a minute timer, and the hotkey uses Carbon. Launch at login uses SMAppService. No special permission is needed for window lists, but Accessibility improves responsiveness and is requested only on demand.

Edge cases and error handling: Full screen apps in their own Space need the overlay to join that Space, so use the collection behavior flags and rebuild windows on active Space change. When the frontmost app has no windows, fade the dimming out. Handle display hot plug by rebuilding overlays on screen parameter change. If the user drags a window, keep the overlay below it by reordering on each window moved event with throttling. Exclusions remove dimming entirely when an excluded app is active. About 350 lines.
