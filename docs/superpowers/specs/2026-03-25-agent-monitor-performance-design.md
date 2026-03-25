# Agent Monitor Theme Performance Fixes

**Date:** 2026-03-25
**Status:** Approved

## Problem

The agent monitor (PokemonScene) SpriteKit theme has two performance issues:

1. **CharacterGenerator never caches sprites** — `generate(sessionID:, size:)` runs ~100 Core Graphics draw operations every time a `CharacterNode` is created, even though the same sessionID + size always produces the same image. With session updates every 2 seconds triggering relayout, this wastes CPU on redundant work.

2. **Per-character Timer objects on the main run loop** — each `CharacterNode` creates up to 3 `Timer` instances (dwell, activate, countdown) that fire on the main run loop. With 10 active sessions, that's 30 timers fragmenting the run loop, competing with SpriteKit's own rendering loop.

## Fix 1: Sprite Caching with NSCache

### File Changed

`Glimpse/CharacterGenerator.swift`

### Design

Add a private static `NSCache` to `CharacterGenerator` that maps `(sessionID, size)` pairs to generated `CGImage` results.

#### Cache Key

String of format `"sessionID:size"` where size is rounded to the nearest integer (e.g. `"abc123:96"`). Rounding avoids cache misses from floating-point drift — `characterSize(for:)` returns continuous `CGFloat` values from division, but sub-pixel differences are visually identical. Uses `NSString` as the key type since `NSCache` requires `AnyObject`-conforming keys.

#### Value Wrapper

`NSCache` requires `AnyObject`-conforming values. Wrap `CGImage` in a minimal class:

```swift
private class CGImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
```

#### Modified `generate()` Flow

1. Build cache key: `"\(sessionID):\(Int(size.rounded()))"` as `NSString`
2. Check cache — if hit, return `box.image`
3. If miss, generate image as before
4. Store result in cache
5. Return image

#### Eviction

No manual eviction needed. `NSCache` automatically purges entries under system memory pressure. Cache is lost on app termination, which is fine — generation is fast for a single character, the problem is doing it repeatedly every 2 seconds.

## Fix 2: Replace Timers with SKActions

### File Changed

`Glimpse/CharacterNode.swift`

### Design

Remove all three `Timer?` properties and replace with named `SKAction` sequences. SpriteKit's action system runs within the rendering loop, avoiding main run loop fragmentation.

#### Properties Removed

```swift
private var dwellTimer: Timer?
private var activateTimer: Timer?
private var countdownTimer: Timer?
```

#### Action Keys

| Old Timer | SKAction Key | Duration | Purpose |
|-----------|-------------|----------|---------|
| `dwellTimer` | `"dwell"` | 0.3s wait | Show hello bubble after brief gaze |
| `activateTimer` | `"activate"` | 3.0s wait | Start countdown after sustained gaze |
| `countdownTimer` | `"countdown"` | 3 × 1.0s sequence | 3-2-1 redirect countdown |

#### `gazeEntered()` — Replaces Timer Scheduling

```
1. Reset hasActivated
2. If bubble not visible:
   - run SKAction.sequence([.wait(0.3), .run { showHello() }]) withKey: "dwell"
3. Run SKAction.sequence([.wait(3.0), .run { startCountdown() }]) withKey: "activate"
```

#### `gazeExited()` — Replaces Timer Invalidation

```
1. removeAction(forKey: "dwell")
2. removeAction(forKey: "activate")
3. cancelCountdown()
4. Reset hasActivated
5. hideHello()
```

#### `startCountdown()` — Replaces Repeating Timer

Build a single `SKAction.sequence` that counts down 3 → 2 → 1 → fire. Refactor `showCountdownText()` to accept an `Int` parameter instead of reading from `self.countdownValue`. The `countdownValue` property can be removed.

```
sequence([
    .run { showCountdownText(3) },
    .wait(1.0),
    .run { showCountdownText(2) },
    .wait(1.0),
    .run { showCountdownText(1) },
    .wait(1.0),
    .run { finishCountdown() }
])
```

Run with key `"countdown"`. The `finishCountdown()` method sets `hasActivated = true`, calls `onActivate?()`, and restores the bubble after 0.5s using an SKAction (not `DispatchQueue.main.asyncAfter`, to stay within SpriteKit's scheduling).

#### `cancelCountdown()` — Replaces Timer Invalidation

```
1. removeAction(forKey: "countdown")
2. Reset isCountingDown
3. Restore bubble style (green tint, original text color)
4. If bubble visible, restore lastOutput text
```

#### `deinit` Simplification

Remove the three `timer?.invalidate()` lines. SKActions are automatically cleaned up when the node is removed from the scene. The `deinit` block can be removed since it has no other work to do.

### Behavioral Equivalence

The timing behavior is identical to the current Timer-based implementation:
- Dwell: 0.3s delay before showing bubble (unchanged)
- Activate: 3.0s sustained gaze before countdown starts (unchanged)
- Countdown: 3 × 1s ticks showing 3, 2, 1 then redirect (unchanged)
- All cancellable on gaze exit (unchanged)

SKAction timing is tied to SpriteKit's frame clock rather than the system wall clock. At 60fps, maximum drift is ~16ms per interval — imperceptible for these durations.

## Scope

- **Files changed:** `CharacterGenerator.swift`, `CharacterNode.swift`
- **No UI changes:** Visual behavior is identical
- **No new dependencies:** Uses `NSCache` (Foundation) and `SKAction` (SpriteKit), both already available
- **No API changes:** `CharacterGenerator.generate()` and `CharacterNode` public interfaces are unchanged

## Edge Cases

- **Memory pressure:** `NSCache` evicts automatically; next `generate()` call simply regenerates and re-caches
- **Rapid gaze enter/exit:** `removeAction(forKey:)` is safe to call even if no action with that key exists
- **Countdown interrupted by gaze exit then re-enter:** Countdown restarts from 3 (same as current behavior — `cancelCountdown()` resets state, new `gazeEntered()` starts fresh activate timer)
- **Node removed during countdown:** SKActions are removed with the node; `[weak self]` in action closures prevents retain cycles
- **Rapid gaze flicker (enter/exit/enter):** Running an SKAction `withKey:` replaces any existing action with that key, so double-entry is self-correcting — no guard needed
- **Cache hit path:** `PokemonScene.relayout()` calls `node.rescale(to:)` which scales the SpriteKit node transform — it does not call `generate()`. The cache is only hit on node creation (new sessions or session count changes), not on every 2-second poll cycle
