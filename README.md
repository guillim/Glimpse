# Glimpse

A native macOS app that displays your active Claude Code sessions as pixel-art characters on your desktop.

Click a character to jump to its terminal window.

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

Select **My Mac** as the run destination and press **Run** (Cmd+R).

The app runs as a background process with no Dock icon. A menu bar icon lets you quit.

| Shortcut | Action |
|----------|--------|
| `Ctrl+X` | Quit |

---

## How it works

Glimpse scans `~/.claude/` for active session logs and renders a character for each running Claude Code instance. Each character shows:

- **Live activity** — reading, writing, running, thinking, searching, spawning, testing, building, committing
- **Idle states** — asking (waiting for input), done, sleeping — with duration timers
- **Project name** — which directory the session is working in
- **Topics** — extracted from recent user messages

Clicking a character activates the parent application (iTerm2, Terminal, VS Code, etc.) and selects the correct tab via AppleScript + tty matching.

---

## Architecture

| File | Role |
|------|------|
| `SessionMonitor.swift` | Polls `~/.claude/` JSONL logs, classifies activity, extracts topics |
| `AgentMonitorScene.swift` | SpriteKit scene — grid layout, click handling, app activation |
| `CharacterNode.swift` | Single character card — sprite, status pill, labels, animations |
| `CharacterGenerator.swift` | Deterministic pixel-art generation from session ID |
| `DesktopWindowController.swift` | Multi-monitor window manager, session monitor ownership, global click monitor |
| `AppDelegate.swift` | Lifecycle, power management, menu bar, keyboard shortcuts |

---

## Features

- Procedurally generated pixel-art characters (deterministic per session ID)
- Adaptive grid layout (1-16+ sessions)
- Color-coded activity status with glowing dot indicators
- Asking state glow ring (pulsing orange) for sessions waiting on user input
- Goodbye animation when sessions end
- Multi-monitor support: characters mirrored on all connected screens, windows created/destroyed automatically
- Click-to-activate: opens the terminal window running the session (works on any screen)
- Pauses rendering during sleep, screensaver, and window occlusion

---

## Performance

Glimpse is designed to stay invisible on your machine: under 10% CPU and under 100 MB RAM, even with several agents running. The rendering loop idles at 3 fps and only briefly boosts to 30 fps when a session changes state, so the GPU is nearly silent between transitions. The tradeoff is that character animations look slightly coarser at rest — unnoticeable at their small pixel-art size.
