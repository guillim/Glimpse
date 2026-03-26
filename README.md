# Glimpse

A native macOS app that displays an agent monitor on your desktop, behind your icons.

No subscription. No external services. All processing happens on-device.

---

## Requirements

- macOS 13.0 or later
- Xcode 15+ (to build from source)

---

## Getting started

```bash
git clone https://github.com/yourname/glimpse.git
cd glimpse
open Glimpse.xcodeproj
```

Select **My Mac** as the run destination and press **Run** (⌘R).

The app has no Dock icon — it runs silently in the background and replaces your desktop wallpaper with the agent monitor. A menu bar icon lets you quit.

| Shortcut | Action |
|----------|--------|
| `Ctrl+X` | Quit |

---

## Features

- **Agent Monitor** — SpriteKit theme that displays active Claude Code sessions as Pokemon-styled characters with live activity status
- **Battery awareness** — Automatically throttles frame rate on battery power to save energy
- **Power management** — Pauses rendering during system sleep, wake, and screensaver

---

## Todo

- [x] Desktop-level window (behind Finder icons, above wallpaper, below all apps)
- [x] No Dock icon, silent background process
- [x] Global keyboard shortcuts
- [x] Status bar icon
- [x] Auto-throttle on battery power
- [x] System sleep/wake and screensaver pause
- [ ] Multi-monitor support
- [ ] Settings panel
- [ ] Launch at login
