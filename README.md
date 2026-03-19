# Holoscape

A native macOS app that turns your desktop into an interactive 3D window. Using your webcam to track your head position in real time, it shifts the perspective of a 3D scene rendered behind your desktop icons — creating the illusion of looking through a physical portal into another world.

No subscription. No external services. All processing happens on-device.

---

## How it works

1. `AVCaptureSession` captures webcam frames at VGA resolution on a dedicated background thread
2. Apple's `Vision` framework (`VNDetectFaceLandmarksRequest`) detects the face bounding box each frame
3. The face center is mapped to a normalized X/Y offset in `[-1, 1]`, and face bounding box width is used as a depth proxy relative to a per-session baseline
4. All three axes are smoothed with a low-pass filter (α = 0.15) to eliminate jitter
5. The smoothed offset drives a `SCNCamera` node inside a `SceneKit` scene, shifting the virtual viewpoint to match the user's head movement
6. The scene renders in a borderless, click-through `NSWindow` pinned at `CGWindowLevelForKey(.desktopWindow) + 1` — above the wallpaper, below Finder icons and all other windows

---

## Requirements

- macOS 13.0 or later
- A Mac with a built-in or external webcam
- Xcode 15+ (to build from source)

---

## Getting started

```bash
git clone https://github.com/yourname/holoscape.git
cd holoscape
open Holoscape/Holoscape.xcodeproj
```

Select **My Mac** as the run destination and press **Run** (⌘R).

Grant camera access when prompted. The app has no Dock icon — it runs silently in the background and replaces your desktop wallpaper with the 3D scene.

**To quit:** press `Ctrl+X` from anywhere, or run:

```bash
killall Holoscape
```

---

## Project structure

```
Holoscape/
├── main.swift                     NSApplication bootstrap — explicit entry point required for projects without storyboards.
├── AppDelegate.swift              Sets activation policy to .accessory (no Dock icon), registers the Ctrl+X global quit shortcut,
│                                  and defers DesktopWindowController creation by one run-loop cycle so NSScreen is ready.
├── DesktopWindowController.swift  Creates a borderless, full-screen NSWindow at desktop window level + 1.
│                                  Uses orderFrontRegardless() since the app is never activated.
│                                  Calls win.setFrame() after setting contentViewController to prevent AppKit from
│                                  collapsing the window to the view controller's preferredContentSize (1×1 by default).
├── HeadTracker.swift              AVCaptureSession + VNDetectFaceLandmarksRequest pipeline.
│                                  Publishes a HeadOffset struct {x, y, z} on the main thread via a callback.
│                                  Depth is estimated by comparing current face bounding-box width to the first-frame baseline.
├── SceneViewController.swift      Owns the SCNView and a procedural deep-space SceneKit scene.
│                                  Receives HeadOffset and moves the camera node accordingly (lateralScale=4, verticalScale=3, depthScale=2).
│                                  Camera always points at the world origin via SCNLookAtConstraint.
└── Info.plist                     NSCameraUsageDescription for camera permission, LSUIElement=true to suppress Dock icon.
```

---

## Known gotchas

| Issue | Cause | Fix applied |
|---|---|---|
| Window invisible (1×1) | `contentViewController =` resizes window to vc's `preferredContentSize` | `win.setFrame(screen.frame)` called after setting the vc |
| App never launches | `@main`/`@NSApplicationMain` don't work on manually created projects without storyboards | Explicit `main.swift` with `NSApplication.shared` + delegate wiring |
| Window above all apps | Window level was set to `.screenSaver` during debug | Restored to `CGWindowLevelForKey(.desktopWindow) + 1` |
| `ignoresApplicationActivated` build error | Removed in macOS 12 | Dropped from `collectionBehavior` |
| `SCNVector3 + Float` type error | `SCNVector3` components are `CGFloat` on macOS | Cast `Float` values with `CGFloat(...)` before arithmetic |

---

## Scenes

Currently ships with one built-in procedural scene: a deep-space environment with a starfield (800 stars), a rotating ringed planet, and a nearby tumbling asteroid. No external assets are required — everything is generated from SceneKit primitives at runtime.

To add a new scene, create a function that returns an `SCNScene` and call it from `SceneViewController.setupScene()`.

---

## Todo

### Done
- [x] macOS desktop-level window (behind Finder icons, above wallpaper, below all apps)
- [x] Real-time head tracking via Apple Vision framework (no third-party deps)
- [x] Low-pass smoothing to eliminate jitter
- [x] Depth estimation from face bounding box size
- [x] Procedural space scene (SceneKit, no assets)
- [x] No Dock icon, no menu bar, silent background process
- [x] Camera permission via `NSCameraUsageDescription`
- [x] Global keyboard shortcut to quit (`Ctrl+X`)

### In progress
- [ ] Status bar icon with basic controls

### Planned
- [ ] Multi-monitor support (choose which display renders the scene)
- [ ] Multiple scenes (forest, interior room, underwater, etc.)
- [ ] Settings panel (tracking sensitivity, depth intensity, FOV)
- [ ] Auto-pause when a window covers the full screen (e.g. during fullscreen apps)
- [ ] Launch at login option
- [ ] Camera selection (useful when multiple webcams are connected)
- [ ] Scene hot-reload / custom `.scn` file drop-in
- [ ] Community scene format (importable packages with assets + metadata)
