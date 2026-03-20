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

Grant camera access when prompted. The app has no Dock icon — it runs silently in the background and replaces your desktop wallpaper with the 3D scene.

| Shortcut | Action |
|----------|--------|
| `Ctrl+S` | Cycle to next scene |
| `Ctrl+X` | Quit |

---

## Scenes

Ships with built-in scenes:

| Scene | Type | Description |
|-------|------|-------------|
| **Space** | Procedural | Starfield, rotating ringed planet, tumbling asteroid |
| **Tahoe** | Parallax photo | Depth-sliced photograph of Lake Tahoe |

Procedural scenes are generated from SceneKit primitives at runtime — no external assets required. Photo scenes use depth-mapped layers for parallax and are **auto-discovered** at launch — no Swift code changes needed to add new ones (see below).

---

## Parallax photo layers

Photos can be converted into multi-layer parallax scenes using a depth map. Each layer is a transparent PNG containing only pixels at a given depth range, stacked at different SceneKit Z positions.

### Step 1 — Add your photo and generate a depth map

Drop your source photo into `public/`, then upload it to **[Depth Anything V2 on Hugging Face](https://huggingface.co/spaces/depth-anything/Depth-Anything-V2)** (free, no account required) and save the depth map alongside it:

```
public/
├── MyPhoto.jpg
└── MyPhoto-depth-map.jpg
```

Any format supported by [sharp](https://sharp.pixelplumbing.com/) works (JPEG, PNG, WebP, TIFF, AVIF, etc.).

### Step 2 — Slice layers

```bash
cd tools && npm install && cd ..

IMAGE=public/MyPhoto.jpg \
DEPTH=public/MyPhoto-depth-map.jpg \
OUTPUT=public/layers/MyPhoto \
NAME=myphoto \
npm run process
```

This slices the image into depth layers inside `public/layers/MyPhoto/`. The `layers/` folder is added to Xcode as a **folder reference** — any new scene folder you add is automatically included in the build.

| Flag | Default | Description |
|------|---------|-------------|
| `LAYERS` | `5` | Number of depth layers (`3`–`6`) |
| `TRANSITION` | `8` | Alpha blend width in depth-value units |

### Step 3 — Build and run

That's it. Rebuild (⌘R) and press `Ctrl+S` to cycle to the new scene.

Parallax scenes are **auto-discovered** at launch: the app scans `layers/` in the bundle for subdirectories containing PNGs matching the `{name}_layer_01_*` convention, parses Z positions from filenames (or reads the `{name}_layers.json` manifest), and builds the scene automatically. No Xcode project changes or Swift code changes required.

---

## Todo

- [x] Desktop-level window (behind Finder icons, above wallpaper, below all apps)
- [x] Real-time head tracking via Apple Vision (no third-party deps)
- [x] Low-pass smoothing + depth estimation from face bounding box
- [x] Procedural space scene (SceneKit, no assets)
- [x] Parallax photo scenes via depth-sliced layers
- [x] Scene cycling at runtime (`Ctrl+S`)
- [x] No Dock icon, silent background process
- [x] Global keyboard shortcuts
- [x] Status bar icon with theme picker
- [ ] Multi-monitor support
- [ ] Settings panel (sensitivity, depth intensity, FOV)
- [ ] Auto-pause during fullscreen apps
- [ ] Launch at login
- [ ] Camera selection (multiple webcams)
