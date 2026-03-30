# Multi-Monitor Mirroring

Mirror the character grid identically on every connected screen, with click-to-activate working on any screen. Windows are created and destroyed automatically as monitors are plugged in or removed.

## Approach

Evolve `DesktopWindowController` from single-window to multi-window manager. One `SessionMonitor` feeds all scenes. Grid layout is computed once and applied identically to every scene.

## Architecture

### ScreenEntry

A value holding the per-screen resources:

```swift
private struct ScreenEntry {
    let window: NSWindow
    let skView: SKView
    let scene: AgentMonitorScene
}
```

`DesktopWindowController` owns a `[NSScreen: ScreenEntry]` dictionary.

### Screen Lifecycle

- On `init` and on `NSApplication.didChangeScreenParametersNotification`, call `syncScreens()`.
- `syncScreens()` diffs `NSScreen.screens` against current entries:
  - **New screen**: create window + SKView + scene, push current sessions.
  - **Removed screen**: tear down window, remove entry.
  - **Changed frame**: resize window and scene to match.
- Screen identity is matched by `NSScreen` object identity (backed by `deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]`).

### SessionMonitor Ownership

Move `SessionMonitor` out of `AgentMonitorScene` and into `DesktopWindowController`. The controller's `onUpdate` callback pushes `[Session]` to every scene via a new method `AgentMonitorScene.updateSessions(_:)`.

`AgentMonitorScene` drops its `sessionMonitor` property and `start()`/`stop()` calls. It becomes a passive renderer.

### Shared Grid Layout

`relayout()`, `characterSize(for:)`, and `columns(for:)` stay in `AgentMonitorScene` — each scene computes its own layout. Since SpriteKit works in points and the layout algorithm is deterministic given the same scene size, all scenes with the same point dimensions produce identical positions.

To guarantee identical positioning across screens of different resolutions: the layout uses `scene.size` which is set from the window frame (in points, not pixels). A 1440-point-wide screen and a 1440-point-wide Retina screen produce the same layout. Screens with different point dimensions (e.g., 1440 vs 1920 points wide) will center the grid independently — the characters appear in the same relative position but the absolute point coordinates differ, which is the correct behavior for differently-sized screens.

### Click Handling

Single global click monitor (unchanged). On click:

1. Get `event.locationInWindow` (screen coordinates for global events).
2. Iterate all `ScreenEntry` values.
3. For each: convert screen point → window point → view point → scene point.
4. Hit-test `scene.characterNode(at:)`.
5. First match wins, call `activateAppForSession`.

### Power Management

- `setPaused(_:)` iterates all entries, sets `skView.isPaused` on each.
- Occlusion observer is set up per window in `addScreen()`.

### AppDelegate Changes

- Still holds one `DesktopWindowController`.
- `onSessionsChanged` callback moves from `agentScene` to the controller.
- `menuItemClicked` calls `activateAppForSession` on the controller, which delegates to any scene (static methods, no scene-specific state).
- `setPaused` calls go to the controller, which fans out to all entries.

## File Changes

| File | Change |
|------|--------|
| `DesktopWindowController.swift` | Multi-window management, screen sync, SessionMonitor ownership, fan-out |
| `AgentMonitorScene.swift` | Remove SessionMonitor, add `updateSessions(_:)`, keep layout logic |
| `AppDelegate.swift` | Wire callbacks to controller instead of single scene |

## Edge Cases

- **App launch with multiple screens**: `syncScreens()` runs on init, creates all windows.
- **All external monitors removed**: only the built-in screen remains, single window — degrades to current behavior.
- **Screen resolution change** (e.g., switching scaled mode): `didChangeScreenParametersNotification` fires, `syncScreens()` resizes the affected window.
- **Clamshell mode**: only the external screen is in `NSScreen.screens`, works naturally.
