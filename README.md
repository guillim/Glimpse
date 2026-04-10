# Glimpse

**Turn your AI agents into Yoda, Luffy or Michael Scott.**

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue?logo=apple&logoColor=white)](#requirements)
[![License: PolyForm NC](https://img.shields.io/badge/license-PolyForm%20NC%201.0-green)](LICENSE)
[![Built with SpriteKit](https://img.shields.io/badge/built%20with-SpriteKit-orange?logo=swift&logoColor=white)](#build-from-source)
[![Download](https://img.shields.io/github/v/release/guillim/Glimpse?label=Download&logo=github)](https://github.com/guillim/Glimpse/releases/latest)

![Glimpse demo](https://guillim.github.io/assets/img/glimpse-one.gif)

Each running Claude Code or Cursor session gets its own fun character — Star Wars, One Piece, Dragon Ball Z, Marvel, Demon Slayer, The Office, or Kawaii.

- Agent is working → your character is active
- Agent needs input → ORANGE glow → click to jump to its terminal
- Agent is done → character idle

No more tab-switching to check on three parallel sessions.

**Free, open source. 100% on-device. No network, no account.**

![Glimpse — animated characters on your desktop](https://guillim.github.io/assets/img/glimpse-hero.gif)

---

## Features

- **7 character styles** — Kawaii, Star Wars, One Piece, Dragon Ball Z, The Office, Marvel, Demon Slayer — with star characters appearing 90% of the time
- **Live activity tracking** — reading, writing, running, thinking, searching, spawning, testing, building, committing
- **Idle state awareness** — asking (waiting for input), done, sleeping — with duration timers
- **Asking state glow** — pulsing orange ring when a session needs your attention
- **Session deduplication** — concurrent sessions on the same project are merged into a single character
- **Session titles** — short hashtags extracted from recent user messages via on-device NLP
- **Click-to-activate** — click any character to jump to its terminal or IDE tab
- **Multi-monitor support** — characters mirrored across all connected screens automatically
- **Cursor IDE support** — detects Cursor sessions alongside Claude Code
- **Menu bar integration** — dropdown listing all active sessions with status and keywords
- **Goodbye animation** — characters wave and fade out when sessions end
- **Power-aware** — pauses rendering during sleep, screensaver, and window occlusion
- **Lightweight** — under 1% CPU, minimal RAM, GPU nearly silent between transitions

---

## Install

Download the latest `.dmg` (1.4 MB) from [Releases](https://github.com/guillim/Glimpse/releases) and drag **Glimpse.app** to your Applications folder.

10-second install. Zero config. Just open it.

The app runs as a background process with no Dock icon. A menu bar icon (top right) shows active sessions and lets you quit.
---

## Future direction

Glimpse today is a monitor. The vision is for it to become a living workspace:

- **Character interactions** — agents working on related projects could acknowledge each other, pass context, or visually cluster together
- **Personality over time** — characters that evolve traits based on how their sessions behave (a fast-committing agent gets a speedster vibe, a long-thinking one meditates)
- **Notifications** — optional sounds or system notifications when an agent needs attention or finishes a big task
- **Session history** — a timeline view of past sessions, what they accomplished, and how long they ran

Contributions toward any of these are welcome.

---

## Contributing

Found a bug or have an idea? [Open an issue](https://github.com/guillim/Glimpse/issues).

Want to contribute code? Fork the repo, create a branch, and open a pull request. There are no formal guidelines yet — just keep things clean and focused.

---

## License

[PolyForm Noncommercial 1.0.0](LICENSE)

You can freely use, modify, and share Glimpse for personal, educational, or non-commercial purposes. Commercial use — including use within a company or as part of a paid product — requires a separate license. Contact the author to discuss commercial terms.
