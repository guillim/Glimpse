# Multi-Monitor Mirroring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mirror the character grid on every connected screen with automatic window creation/destruction on monitor changes.

**Architecture:** Evolve `DesktopWindowController` from single-window to multi-window manager using a `[CGDirectDisplayID: ScreenEntry]` dictionary. Move `SessionMonitor` ownership from `AgentMonitorScene` into the controller. Update `AppDelegate` to wire callbacks through the controller.

**Tech Stack:** AppKit (NSScreen, NSWindow), SpriteKit (SKView, SKScene)

---

### Task 1: Make AgentMonitorScene a passive renderer

Remove `SessionMonitor` from `AgentMonitorScene` and add a public `updateSessions(_:)` method so the scene can be driven externally.

**Files:**
- Modify: `Glimpse/AgentMonitorScene.swift`

- [ ] **Step 1: Remove SessionMonitor ownership and add updateSessions**

Replace the `sessionMonitor` property, `didMove(to:)`, `willMove(from:)`, and `onSessionsChanged` with a passive API:

```swift
// DELETE these lines:
//   private let sessionMonitor = SessionMonitor()
//   var onSessionsChanged: (([SessionMonitor.Session]) -> Void)?

// REPLACE didMove(to:) with:
override func didMove(to view: SKView) {
    backgroundColor = .clear
    addChild(emptyLabel)
    emptyLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
}

// DELETE willMove(from:) entirely (it only called sessionMonitor.stop())

// ADD new public method:
/// Push session data from an external SessionMonitor.
func updateSessions(_ sessions: [SessionMonitor.Session]) {
    handleSessionUpdate(sessions)
}
```

- [ ] **Step 2: Build and verify compilation**

Run: `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug build 2>&1 | tail -20`

Expected: Build succeeds. (The app won't poll on its own anymore — that's expected, Task 2 restores it.)

- [ ] **Step 3: Commit**

```bash
git add Glimpse/AgentMonitorScene.swift
git commit -m "refactor: make AgentMonitorScene a passive renderer

Remove SessionMonitor ownership. Add updateSessions(_:) so the scene
can be driven externally by DesktopWindowController."
```

---

### Task 2: Rewrite DesktopWindowController for multi-monitor

Replace the single-window controller with a multi-window manager that owns the `SessionMonitor` and syncs windows to connected screens.

**Files:**
- Modify: `Glimpse/DesktopWindowController.swift`

- [ ] **Step 1: Replace the entire file with the multi-window implementation**

```swift
import AppKit
import SpriteKit

/// Manages one borderless desktop-level window per connected screen,
/// each hosting a mirrored SpriteKit scene of agent characters.
final class DesktopWindowController {

    /// Per-screen resources.
    private struct ScreenEntry {
        let window: NSWindow
        let skView: SKView
        let scene: AgentMonitorScene
    }

    /// Active screen entries keyed by display ID (stable across NSScreen instances).
    private var entries: [CGDirectDisplayID: ScreenEntry] = [:]

    private let sessionMonitor = SessionMonitor()
    private var latestSessions: [SessionMonitor.Session] = []
    private var clickMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    /// Called on the main thread with current sessions — used by AppDelegate for menu bar.
    var onSessionsChanged: (([SessionMonitor.Session]) -> Void)?

    init() {
        setupClickMonitor()
        observeScreenChanges()
        syncScreens()
        startMonitoring()
    }

    deinit {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        sessionMonitor.stop()
        for entry in entries.values {
            entry.window.orderOut(nil)
        }
    }

    // MARK: - Session Monitoring

    private func startMonitoring() {
        sessionMonitor.onUpdate = { [weak self] sessions in
            guard let self else { return }
            self.latestSessions = sessions
            for entry in self.entries.values {
                entry.scene.updateSessions(sessions)
            }
            self.onSessionsChanged?(sessions)
        }
        sessionMonitor.start()
    }

    // MARK: - Screen Sync

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncScreens()
        }
    }

    private func syncScreens() {
        let currentScreens = NSScreen.screens
        var currentDisplayIDs = Set<CGDirectDisplayID>()

        for screen in currentScreens {
            let displayID = Self.displayID(for: screen)
            currentDisplayIDs.insert(displayID)

            if let existing = entries[displayID] {
                // Screen still present — update frame if changed
                let frame = screen.frame
                if existing.window.frame != frame {
                    existing.window.setFrame(frame, display: true)
                    existing.scene.size = frame.size
                }
            } else {
                // New screen — create entry
                let entry = makeScreenEntry(for: screen)
                entries[displayID] = entry
                entry.scene.updateSessions(latestSessions)
            }
        }

        // Remove entries for disconnected screens
        let staleIDs = Set(entries.keys).subtracting(currentDisplayIDs)
        for id in staleIDs {
            if let entry = entries.removeValue(forKey: id) {
                entry.window.orderOut(nil)
            }
        }
    }

    private func makeScreenEntry(for screen: NSScreen) -> ScreenEntry {
        let frame = screen.frame

        let win = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        win.collectionBehavior = [.stationary, .canJoinAllSpaces]
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.backgroundColor = .clear
        win.setFrame(frame, display: false)
        win.orderFrontRegardless()

        let sv = SKView(frame: CGRect(origin: .zero, size: frame.size))
        sv.autoresizingMask = [.width, .height]
        sv.allowsTransparency = true
        sv.preferredFramesPerSecond = 30
        win.contentView?.addSubview(sv)

        let scene = AgentMonitorScene(size: frame.size)
        scene.scaleMode = .resizeFill
        sv.presentScene(scene)

        setupOcclusionObserver(for: win, skView: sv)

        return ScreenEntry(window: win, skView: sv, scene: scene)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    // MARK: - Click Monitor

    private func setupClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleGlobalClick(event)
        }
    }

    private func handleGlobalClick(_ event: NSEvent) {
        let screenPoint = event.locationInWindow

        for entry in entries.values {
            let windowPoint = entry.window.convertPoint(fromScreen: screenPoint)
            let viewPoint = entry.skView.convert(windowPoint, from: nil)
            let scenePoint = entry.scene.convertPoint(fromView: viewPoint)

            if let node = entry.scene.characterNode(at: scenePoint) {
                entry.scene.activateAppForSession(node.sessionID)
                return
            }
        }
    }

    // MARK: - Power Management

    func setPaused(_ paused: Bool) {
        for entry in entries.values {
            entry.skView.isPaused = paused
        }
    }

    // MARK: - Occlusion

    private func setupOcclusionObserver(for window: NSWindow, skView: SKView) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { _ in
            let visible = window.occlusionState.contains(.visible)
            skView.isPaused = !visible
        }
    }

    // MARK: - App Activation (forwarded from AppDelegate menu)

    func activateAppForSession(_ sessionID: String) {
        entries.values.first?.scene.activateAppForSession(sessionID)
    }
}
```

- [ ] **Step 2: Build and verify compilation**

Run: `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug build 2>&1 | tail -20`

Expected: Build succeeds. (AppDelegate still references old API — fixed in Task 3.)

- [ ] **Step 3: Commit**

```bash
git add Glimpse/DesktopWindowController.swift
git commit -m "feat: rewrite DesktopWindowController for multi-monitor support

Manage one window per connected screen. Own SessionMonitor and fan out
session updates to all scenes. Auto-create/destroy windows on screen
changes via didChangeScreenParametersNotification."
```

---

### Task 3: Update AppDelegate to use new controller API

Wire `AppDelegate` to the new `DesktopWindowController` which is no longer an `NSWindowController` subclass.

**Files:**
- Modify: `Glimpse/AppDelegate.swift`

- [ ] **Step 1: Update AppDelegate to use the new API**

Replace the `applicationDidFinishLaunching` body and `menuItemClicked`:

```swift
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var desktopWindowController: DesktopWindowController?
    private var keyMonitor: Any?
    private var statusItem: NSStatusItem?
    private var currentSessions: [SessionMonitor.Session] = []
    private var normalIcon: NSImage?
    private var badgedIcon: NSImage?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupKeyboardShortcut()
        setupPowerNotifications()
        DispatchQueue.main.async {
            let controller = DesktopWindowController()
            self.desktopWindowController = controller
            self.setupMenuBarItem()
            controller.onSessionsChanged = { [weak self] sessions in
                self?.currentSessions = sessions
                self?.rebuildMenu()
            }
        }
    }

    // ... applicationWillTerminate, applicationShouldTerminateAfterLastWindowClosed unchanged ...

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let sessionID = sender.representedObject as? String else { return }
        desktopWindowController?.activateAppForSession(sessionID)
    }

    // ... all other methods unchanged ...
}
```

The key changes:
1. Remove `showWindow(nil)` call (controller creates windows in `init`).
2. Wire `onSessionsChanged` to the controller directly instead of `agentScene`.
3. `menuItemClicked` calls `activateAppForSession` on the controller.

- [ ] **Step 2: Build and verify compilation**

Run: `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug build 2>&1 | tail -20`

Expected: Build succeeds with no errors or warnings.

- [ ] **Step 3: Commit**

```bash
git add Glimpse/AppDelegate.swift
git commit -m "feat: wire AppDelegate to multi-monitor controller

Use new DesktopWindowController API — onSessionsChanged and
activateAppForSession are now on the controller, not a single scene."
```

---

### Task 4: Manual testing and edge cases

Verify the implementation works correctly across monitor configurations.

**Files:**
- None (testing only)

- [ ] **Step 1: Build and run the app**

Run: `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug build 2>&1 | tail -20`

Then launch the built app:
```bash
open $(xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')/Glimpse.app
```

- [ ] **Step 2: Verify single-monitor behavior**

With only one screen connected:
- Characters should appear on the desktop as before.
- Click-to-activate should work.
- Menu bar icon and session list should work.

- [ ] **Step 3: Verify multi-monitor behavior (if external monitor available)**

With an external monitor connected:
- Characters should appear on both screens.
- Click-to-activate should work on either screen.
- Unplug the external monitor — the extra window should disappear, primary screen keeps working.
- Plug it back in — a new window should appear with characters.

- [ ] **Step 4: Commit final state**

```bash
git add -A
git commit -m "feat: multi-monitor mirroring complete

Characters now appear on all connected screens. Windows are created and
destroyed automatically when monitors are plugged in or removed."
```
