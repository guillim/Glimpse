# Glimpse

A native macOS app that turns your desktop into an interactive 3D window. Using your webcam to track your head position in real time, it shifts the perspective of a 3D scene rendered behind your desktop icons — creating the illusion of looking through a physical portal into another world.

No subscription. No external services. All processing happens on-device.

---

## Requirements

- macOS 13.0 or later
- A Mac with a built-in or external webcam
- Xcode 15+ (to build from source)

---

## Getting started

```bash
git clone https://github.com/yourname/glimpse.git
cd glimpse
open Glimpse.xcodeproj
```

Select **My Mac** as the run destination and press **Run** (⌘R).

Grant camera access when prompted. The app has no Dock icon — it runs silently in the background and replaces your desktop wallpaper with the 3D scene. A menu bar icon lets you switch themes, import custom models, and quit.

| Shortcut | Action |
|----------|--------|
| `Ctrl+S` | Cycle to next scene |
| `Ctrl+X` | Quit |

---

## Scenes

Scenes are **auto-discovered** at launch — no code changes needed to add new ones. The app ships with:

| Scene | Description |
|-------|-------------|
| **Basketball** | USDZ basketball (default scene) |
| **Chameleon** | USDZ chameleon |
| **Chess** | USDZ chess set |
| **Guitare** | USDZ guitar |
| **Sea** | USDZ ocean scene |
| **Tomb** | USDZ tomb sculpture |
| **Tree** | USDZ tree |

3D models are loaded from `public/models/` and rendered with three-point lighting. Head tracking rotates the model to follow your viewpoint.

---

## Custom models

You can import your own 3D models at runtime via the menu bar: **Theme > Import Custom Model...**

Supported formats: `.usdz`, `.obj`, `.dae`, `.scn`

Imported models are copied to `~/Library/Application Support/Glimpse/models/` and persist across launches. Custom models can be deleted from the Theme submenu.

---

## Features

- **Head tracking** — Real-time face detection via Apple Vision framework at 60 fps, with Kalman filtering and frame-rate-aware exponential smoothing
- **Off-axis projection** — Physically correct asymmetric frustum that makes the screen behave like a real window
- **3D model support** — Loads `.usdz`, `.obj`, `.dae`, `.scn` files with head-driven rotation
- **Scene persistence** — Remembers your last selected scene across launches
- **Battery awareness** — Automatically throttles to 30 fps on battery power to save energy
- **Power management** — Pauses rendering and tracking during system sleep, wake, and screensaver
- **Custom model import** — Import and delete your own 3D models from the menu bar
- **Menu bar control** — Theme picker with checkmarks, scene cycling, and quit

---

## Technical priorities

Any change to the head tracking or rendering pipeline **must** preserve these two priorities, in order:

1. **Smoothness** — The parallax animation must be perfectly fluid with zero visible frame jumps. A "frame jump" is any discontinuity where the camera position snaps between two frames rather than gliding. This is the #1 priority because frame jumps look like bugs and break the illusion entirely. Every filtering, prediction, and rendering decision should be evaluated against this constraint first.

2. **Latency** — The delay between a physical head movement and the corresponding on-screen camera shift should be as low as possible. Lower latency makes the parallax feel "real" and connected to the user's body. However, latency reduction must never come at the cost of smoothness — a slightly laggy but perfectly smooth animation is always preferable to a low-latency but jittery one.

When these two goals conflict, smoothness wins.

---

## Todo

- [x] Desktop-level window (behind Finder icons, above wallpaper, below all apps)
- [x] Real-time head tracking via Apple Vision (no third-party deps)
- [x] Kalman filtering + depth estimation from face bounding box
- [x] 3D model scenes with head-driven rotation
- [x] Scene cycling at runtime (`Ctrl+S`)
- [x] No Dock icon, silent background process
- [x] Global keyboard shortcuts
- [x] Status bar icon with theme picker
- [x] Scene persistence across launches
- [x] Custom model import and deletion
- [x] Auto-throttle on battery power
- [x] System sleep/wake and screensaver pause
- [ ] Multi-monitor support
- [ ] Settings panel (sensitivity, depth intensity, FOV)
- [ ] Launch at login
- [ ] Smooth scene transitions
- [ ] Thumbnail previews in theme menu
