# Glimpse

**Your AI agents, alive on your desktop.**

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue?logo=apple&logoColor=white)](#requirements)
[![License: PolyForm NC](https://img.shields.io/badge/license-PolyForm%20NC%201.0-green)](LICENSE)
[![Built with SpriteKit](https://img.shields.io/badge/built%20with-SpriteKit-orange?logo=swift&logoColor=white)](#architecture)

A native macOS app that turns your active Claude Code and Cursor sessions into pixel-art characters living on your desktop. Each character shows what its agent is doing in real time — and clicking one takes you straight to its terminal window.

**No subscription. No external services. Everything runs on your Mac.**

![Glimpse screenshot — four pixel-art characters on the desktop](docs/images/screenshot.png)

---

## Why?

AI agents work invisibly in your terminal. You don't know what they're doing, when they need your input, or when they're done. Tab-switching to check on three parallel Claude sessions gets old fast.

Glimpse gives you a persistent, at-a-glance view of all your agents — right on the desktop, across all monitors. When a character starts glowing orange, it needs you. When it waves goodbye, it's done.

---

## Features

- **Pixel-art characters** — procedurally generated from session ID, deterministic and unique
- **Live activity tracking** — reading, writing, running, thinking, searching, spawning, testing, building, committing
- **Idle state awareness** — asking (waiting for input), done, sleeping — with duration timers
- **Asking state glow** — pulsing orange ring when a session needs your attention
- **Session titles** — short hashtags extracted from recent user messages via on-device NLP
- **Click-to-activate** — click any character to jump to its terminal or IDE tab
- **Multi-monitor support** — characters mirrored across all connected screens automatically
- **Cursor IDE support** — detects Cursor sessions alongside Claude Code
- **Menu bar integration** — dropdown listing all active sessions with status and keywords
- **Goodbye animation** — characters wave and fade out when sessions end
- **Power-aware** — pauses rendering during sleep, screensaver, and window occlusion
- **Lightweight** — under 10% CPU, under 100 MB RAM, GPU nearly silent between transitions

---

## Install

Download the latest release from [Releases](https://github.com/guillim/Glimpse/releases) and drag **Glimpse.app** to your Applications folder.

The app runs as a background process with no Dock icon. A menu bar icon (top right) shows active sessions and lets you quit.

| Shortcut | Action |
|----------|--------|
| `Ctrl+X` | Quit |

---

## How it works

Glimpse scans `~/.claude/` for active session logs and renders a character for each running Claude Code instance. Each character shows:

- **Live activity** — what the agent is currently doing
- **Project name** — which directory the session is working in
- **Session title** — a short title extracted from the most recent user messages

Clicking a character activates the parent application (iTerm2, Terminal, Cursor, etc.) and selects the correct tab via AppleScript + tty matching.

---

## Future direction

Glimpse today is a monitor. The vision is for it to become a living workspace:

- **Character interactions** — agents working on related projects could acknowledge each other, pass context, or visually cluster together
- **Personality over time** — characters that evolve traits based on how their sessions behave (a fast-committing agent gets a speedster vibe, a long-thinking one meditates)
- **Notifications** — optional sounds or system notifications when an agent needs attention or finishes a big task
- **Session history** — a timeline view of past sessions, what they accomplished, and how long they ran

Contributions toward any of these are welcome.

---

## Known limitations

- macOS only (relies on SpriteKit and AppKit)
- Requires Claude Code sessions writing to `~/.claude/` — won't detect other AI coding tools (except Cursor)
- Menu bar icon does not auto-switch between light and dark appearance
- No prebuilt binary yet — must build from source (see below)

---

## Build from source

**Requirements:** macOS 13.0+, Xcode 15+

```bash
git clone https://github.com/guillim/Glimpse.git
cd Glimpse
open Glimpse.xcodeproj
```

Select **My Mac** as the run destination and press **Run** (Cmd+R).

### Architecture

| File | Role |
|------|------|
| `SessionMonitor.swift` | Polls `~/.claude/` JSONL logs, classifies activity, extracts session titles via NLTagger |
| `CursorSessionProvider.swift` | Discovers active Cursor IDE sessions via LSP socket scanning |
| `AgentMonitorScene.swift` | SpriteKit scene — grid layout, click handling, app activation |
| `CharacterNode.swift` | Single character card — sprite, status pill, labels, animations |
| `CharacterGenerator.swift` | Deterministic pixel-art generation from session ID |
| `DesktopWindowController.swift` | Multi-monitor window manager, session monitor ownership, global click monitor |
| `AppDelegate.swift` | Lifecycle, power management, menu bar, keyboard shortcuts |

---

## Contributing

Found a bug or have an idea? [Open an issue](https://github.com/guillim/Glimpse/issues).

Want to contribute code? Fork the repo, create a branch, and open a pull request. There are no formal guidelines yet — just keep things clean and focused.

---

## License

[PolyForm Noncommercial 1.0.0](LICENSE)

You can freely use, modify, and share Glimpse for personal, educational, or non-commercial purposes. Commercial use — including use within a company or as part of a paid product — requires a separate license. Contact the author to discuss commercial terms.
