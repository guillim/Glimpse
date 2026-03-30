# Menu Bar Agent List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the menu bar dropdown to list all active agent sessions with activity state, bell icon when asking, and orange badge dot on the status item icon.

**Architecture:** AppDelegate subscribes to session updates from AgentMonitorScene via a new callback, rebuilds the NSMenu on each update, and composites a badge onto the status item icon when any session is asking. Click actions reuse the existing `activateAppForSession` method.

**Tech Stack:** AppKit (NSStatusItem, NSMenu, NSMenuItem, NSImage), Swift

---

### Task 1: Expose Session Updates from AgentMonitorScene

**Files:**
- Modify: `Glimpse/AgentMonitorScene.swift:32-35`

AgentMonitorScene currently consumes session updates internally. Add a public callback so AppDelegate can also receive them.

- [ ] **Step 1: Add a public onMenuUpdate callback**

In `AgentMonitorScene`, add a public property after the `emptyLabel` declaration (after line 23):

```swift
/// Called on the main thread with current sessions — used by AppDelegate for menu bar.
var onSessionsChanged: (([SessionMonitor.Session]) -> Void)?
```

- [ ] **Step 2: Forward session updates to the new callback**

In `didMove(to:)`, inside the existing `sessionMonitor.onUpdate` closure, add a call to `onSessionsChanged` after calling `handleSessionUpdate`:

Replace the closure at lines 32-34:
```swift
sessionMonitor.onUpdate = { [weak self] sessions in
    self?.handleSessionUpdate(sessions)
    self?.onSessionsChanged?(sessions)
}
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Glimpse/AgentMonitorScene.swift
git commit -m "feat: expose session update callback from AgentMonitorScene"
```

---

### Task 2: Build Dynamic Menu with Agent Rows

**Files:**
- Modify: `Glimpse/AppDelegate.swift`

Replace the static "Exit"-only menu with a dynamically rebuilt menu listing all active sessions.

- [ ] **Step 1: Add a property to store current sessions**

In `AppDelegate`, add after the `statusItem` property (line 7):

```swift
private var currentSessions: [SessionMonitor.Session] = []
```

- [ ] **Step 2: Subscribe to session updates in applicationDidFinishLaunching**

After `self.setupMenuBarItem()` (line 16), add:

```swift
self.desktopWindowController?.agentScene?.onSessionsChanged = { [weak self] sessions in
    self?.currentSessions = sessions
    self?.rebuildMenu()
}
```

- [ ] **Step 3: Add the rebuildMenu method**

Add this method to AppDelegate after `setupMenuBarItem()`:

```swift
private func rebuildMenu() {
    let menu = NSMenu()

    if currentSessions.isEmpty {
        let noAgents = NSMenuItem(title: "No agents active", action: nil, keyEquivalent: "")
        noAgents.isEnabled = false
        menu.addItem(noAgents)
    } else {
        for session in currentSessions {
            let activityLabel = activityString(session.activity)
            let isAsking = session.activity == .asking

            let title = "\(session.projectName)  \(activityLabel)\(isAsking ? "  🔔" : "")"
            let item = NSMenuItem(title: title, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = session.id
            menu.addItem(item)
        }
    }

    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Exit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    statusItem?.menu = menu
}

@objc private func menuItemClicked(_ sender: NSMenuItem) {
    guard let sessionID = sender.representedObject as? String else { return }
    desktopWindowController?.agentScene?.activateAppForSession(sessionID)
}

private func activityString(_ activity: SessionMonitor.Activity) -> String {
    switch activity {
    case .reading:    return "reading"
    case .writing:    return "writing"
    case .running:    return "running"
    case .testing:    return "testing"
    case .building:   return "building"
    case .committing: return "committing"
    case .thinking:   return "thinking"
    case .processing: return "processing"
    case .spawning:   return "spawning"
    case .searching:  return "searching"
    case .asking:     return "asking"
    case .done:       return "done"
    case .sleeping:   return "idle"
    }
}
```

- [ ] **Step 4: Remove old static menu items from setupMenuBarItem**

Replace lines 56-58 in the existing `setupMenuBarItem()`:
```swift
let menu = NSMenu()
menu.addItem(NSMenuItem(title: "Exit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
statusItem?.menu = menu
```

With just:
```swift
rebuildMenu()
```

- [ ] **Step 5: Verify it compiles**

Run: `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Glimpse/AppDelegate.swift
git commit -m "feat: dynamic menu bar listing active agent sessions"
```

---

### Task 3: Orange Badge Dot on Status Item Icon

**Files:**
- Modify: `Glimpse/AppDelegate.swift`

Add a small orange dot to the top-right of the menu bar icon when any session has `activity == .asking`.

- [ ] **Step 1: Add icon caching properties**

Add after `currentSessions` property:

```swift
private var normalIcon: NSImage?
private var badgedIcon: NSImage?
```

- [ ] **Step 2: Create the icon compositing method**

Add to AppDelegate:

```swift
private func makeIcon(badge: Bool) -> NSImage? {
    guard let baseImage = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Glimpse") else {
        return nil
    }

    let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
    let configured = baseImage.withSymbolConfiguration(config) ?? baseImage

    guard badge else { return configured }

    let size = configured.size
    let result = NSImage(size: size, flipped: false) { rect in
        configured.draw(in: rect)
        let dotSize: CGFloat = 5
        let dotRect = NSRect(
            x: size.width - dotSize - 0.5,
            y: size.height - dotSize - 0.5,
            width: dotSize,
            height: dotSize
        )
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        return true
    }
    result.isTemplate = false
    return result
}
```

- [ ] **Step 3: Initialize cached icons in setupMenuBarItem**

In `setupMenuBarItem()`, replace the image assignment:
```swift
if let button = statusItem?.button {
    button.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Glimpse")
}
```

With:
```swift
normalIcon = makeIcon(badge: false)
badgedIcon = makeIcon(badge: true)
if let button = statusItem?.button {
    button.image = normalIcon
}
```

- [ ] **Step 4: Update the icon in rebuildMenu**

At the end of `rebuildMenu()`, before the closing brace, add:

```swift
let anyAsking = currentSessions.contains { $0.activity == .asking }
statusItem?.button?.image = anyAsking ? badgedIcon : normalIcon
```

- [ ] **Step 5: Verify it compiles**

Run: `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Glimpse/AppDelegate.swift
git commit -m "feat: orange badge dot on menu bar icon when agent is asking"
```
