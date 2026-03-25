# Pokemon Session Monitor Theme — Design Spec

## Overview

A new Glimpse theme that displays procedurally generated Pokemon-styled pixel art characters on a dark background, where each character represents an active Claude Code session on the laptop. Characters update their status every 5 seconds by reading session logs, and respond to head tracking gaze with a hello greeting.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Art style | DS/Modern pixel (64–96px) | Large enough for expressive status indicators |
| Asset source | Procedurally generated (Core Graphics) | No external assets, infinite unique characters |
| Grid layout | Adaptive grid | Scales from 1 session (large centered) to 10+ (compact grid) |
| Hello interaction | Gaze-enter with 300ms dwell | Hover-like, smooth fade in/out, avoids accidental triggers |
| Hello message | Generic ("Hello!") | Simple, not noisy |
| Rendering engine | SpriteKit (SKScene) | Lowest RAM for 2D sprites, purpose-built for this use case |
| Session log source | `~/.claude/` JSONL files | Cursor support deferred (see TODO.md) |

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    AppDelegate                            │
│  Menu Bar → Theme Switch → View Swap (SCNView ↔ SKView)  │
│                                      │                   │
│  ┌───────────────────────────────────▼────────────────┐  │
│  │          DesktopWindowController                    │  │
│  │  contentView = SCNView (3D) OR SKView (Pokemon)    │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘

┌─ Pokemon Theme ──────────────────────────────────────────┐
│                                                          │
│  PokemonScene (SKScene)                                  │
│    ├── Dark background                                   │
│    ├── CharacterNode[] (adaptive grid)                   │
│    ├── Empty-state label                                 │
│    └── update() → gaze hit-testing                       │
│              │                                           │
│  SessionMonitor ──(5s timer)──▶ scan ~/.claude/ JSONL    │
│              │                                           │
│  CharacterGenerator: sessionID → CGImage                 │
│              │                                           │
│  HeadTracker (existing, zero changes)                    │
└──────────────────────────────────────────────────────────┘
```

### Components

**PokemonScene.swift** — `SKScene` subclass. Owns the grid layout, character nodes, and empty-state message. In its `update(_:currentTime:)` callback, reads HeadTracker offset, maps to gaze coordinates, and hit-tests characters for the hello interaction.

**SessionMonitor.swift** — Runs a background `Timer` every 5 seconds. Scans `~/.claude/projects/*/` for `.jsonl` session files. For each active session, reads the last ~10 lines to classify activity state. Notifies PokemonScene of session changes (added, removed, state updated) via a delegate or closure.

**CharacterNode.swift** — `SKNode` subclass wrapping:
- Body sprite (`SKSpriteNode` from procedurally generated `CGImage`)
- Status icon (top-right: book, speech bubble, question mark, or zzz)
- Hello bubble (top-center, fades in/out on gaze)
- Project label (bottom, monospace text)
- Handles its own animations: status transitions, hello fade, goodbye fadeout

**CharacterGenerator.swift** — Pure function: `sessionID → CGImage`. Hashes the session UUID to seed a deterministic RNG. Draws a unique Pokemon-styled creature using Core Graphics with randomized traits: body shape, color, eye style, ears/horns, tail, mouth, cheek marks.

### Modified Files

- **SceneViewController.swift** — Add Pokemon as a `SceneEntry`. Detect SpriteKit themes and manage SKView creation/swap instead of loading an SCNScene.
- **AppDelegate.swift** — Pokemon entry appears in the theme menu alongside 3D models.
- **DesktopWindowController.swift** — Support SKView as contentView (same window properties: borderless, click-through, desktop level).

---

## Session Monitoring

### Discovery

1. Glob all `*.jsonl` files in `~/.claude/projects/*/` (depth 1 only, skip `subagents/` directories)
2. Check last-modified time for each file
3. Classify:
   - **Active**: modified within last 5 minutes
   - **Stale**: modified 5–10 minutes ago → fade-out candidate
   - **Dead**: modified 10+ minutes ago → ignore

### Activity Detection

Read the last ~10 lines of each active session's JSONL file. Classify based on the most recent messages:

| State | Condition | Icon |
|-------|-----------|------|
| **Reading** | Last assistant message contains `tool_use` with name in: `Read`, `Glob`, `Grep` | Book |
| **Talking** | Last assistant message contains a `text` content block | Speech bubble |
| **Waiting** | Last message is `assistant` with `stop_reason: "end_turn"` and no new messages for 30+ seconds | Question mark |
| **Sleeping** | Default/fallback — session active but no activity for 2+ minutes | Zzz |

### Topic Label

Extract project name from the directory path:
- `-Users-gui-github-background` → `"background"`
- `-Users-gui-github-paul` → `"paul"`

Simple split on `-` and take the last component.

### Session Lifecycle

| Event | Behavior |
|-------|----------|
| New session appears | CharacterGenerator creates unique creature. Character fades in (0.5s). Grid relayouts with animated positions (0.3s). |
| Session active | Status icon updates every 5s poll. Smooth crossfade between status icons. |
| Session ends | "Goodbye!" text appears above character for 5 seconds, then character fades out (1s). Grid relayouts. |
| No sessions | Centered text on dark background: *"No Claude sessions active — start one to see your Pokemon!"* |

---

## Procedural Character Generator

### Input/Output

- **Input**: Session ID (UUID string)
- **Output**: `CGImage` (64–96px, transparent background)
- **Deterministic**: Same session ID always produces the same character

### Trait Randomization

Hash the session UUID to produce a deterministic seed. From the seed, select:

| Trait | Options |
|-------|---------|
| Body shape | Round, Oval, Square-ish, Blob |
| Body color | Yellow, Red, Blue, Green, Purple, Orange, Pink, Teal, Brown |
| Eye style | Dot, Circle, Anime, Sleepy |
| Ear/horn | Pointy, Round, Antenna, None |
| Tail | Lightning, Swirl, Flame, None |
| Mouth | Smile, Open, Cat-mouth, Line |
| Cheek marks | Circles, Triangles, None |
| Accent color | Contrasting belly/ear tips |

**~200 unique visual combinations.**

### Drawing Order (Core Graphics)

1. Body fill (main shape + color)
2. Accent patches (belly, ear tips)
3. Eyes (with highlight dot for life)
4. Mouth
5. Ears/horns
6. Tail
7. Cheek marks (optional)

---

## Adaptive Grid Layout

### Scaling Rules

| Session count | Columns | Character size | Layout |
|---------------|---------|---------------|--------|
| 1 | 1 | 96px | Centered |
| 2–4 | count | 80px | Single row, centered |
| 5–9 | 3 | 64px | Multi-row grid |
| 10–16 | 4 | 48px | Compact grid |
| 17+ | 5 | 48px | Dense grid |

### Algorithm

```
cols = 1           if count == 1
cols = count       if count <= 4
cols = 3           if count <= 9
cols = 4           if count <= 16
cols = 5           if count > 16

rows = ceil(count / cols)

cellW = screenWidth / cols
cellH = screenHeight / rows
charSize = min(cellW, cellH) * 0.55
charSize = clamp(charSize, 48, 96)
```

Grid is centered on screen. Each cell contains: character body + status icon + label. Position changes animate with `SKAction.move(to:duration:)` over 0.3s with ease-in-out timing.

---

## Gaze Interaction (Hello)

### Head Tracking Integration

HeadTracker requires **zero changes**. Both `SCNSceneRendererDelegate.renderer(_:updateAtTime:)` and `SKScene.update(_:)` run once per frame. PokemonScene reads the same `latestOffset` and `latestVelocity` properties.

### Gaze Mapping

```
gazeX = screenWidth  * 0.5 + offset.x * screenWidth  * 0.5
gazeY = screenHeight * 0.5 + offset.y * screenHeight * 0.5
```

### Hit Testing

Per frame in `SKScene.update(_:)`:
1. Convert gaze point to scene coordinates
2. Find nearest CharacterNode within hitbox radius (character size × 1.5)
3. If character found AND not already focused → start 300ms dwell timer
4. If same character still focused after 300ms → trigger hello bubble fade-in (0.3s)
5. If gaze leaves hitbox → cancel dwell timer → fade out hello bubble (0.3s)

Performance: O(n) distance check where n = session count. Trivial for <20 sessions.

---

## View Swapping

### Switch to Pokemon Theme

1. User selects "Pokemon" from menu
2. SceneViewController detects SpriteKit theme
3. Pause current SCNView rendering
4. Create SKView (or reuse cached instance)
5. `skView.presentScene(pokemonScene)`
6. Swap `window.contentView = skView`
7. Release old SCNScene to free memory
8. Start SessionMonitor polling

### Switch Back to 3D Theme

1. Stop SessionMonitor polling
2. Swap `window.contentView = scnView`
3. Load new 3D scene as usual
4. Release SKScene + SKView

Both views share the same HeadTracker instance. Window properties (level, click-through, borderless) are unchanged.

---

## New Files

| File | Purpose |
|------|---------|
| `Glimpse/PokemonScene.swift` | SKScene — grid layout, update loop, empty state, gaze hit-testing |
| `Glimpse/SessionMonitor.swift` | Timer-based JSONL scanner, activity classification, session lifecycle |
| `Glimpse/CharacterNode.swift` | SKNode — body sprite, status icon, label, hello bubble, animations |
| `Glimpse/CharacterGenerator.swift` | Pure function: sessionID → CGImage via Core Graphics |
| `TODO.md` | Track deferred work (Cursor session support, etc.) |

## Modified Files

| File | Changes |
|------|---------|
| `Glimpse/SceneViewController.swift` | Add Pokemon SceneEntry, view swap logic for SKView |
| `Glimpse/AppDelegate.swift` | Pokemon entry in theme menu |
| `Glimpse/DesktopWindowController.swift` | Support SKView as contentView |
| `Glimpse.xcodeproj/project.pbxproj` | Add new Swift files to build |
