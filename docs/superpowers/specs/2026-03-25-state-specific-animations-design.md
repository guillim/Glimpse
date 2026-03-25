# State-Specific Character Animations

**Date:** 2026-03-25
**Status:** Approved

## Problem

Every character in the agent monitor plays the same gentle breathing animation regardless of activity state. The only visual differentiator between states is the emoji/text label crossfade. Users cannot tell what agents are doing from motion alone — they must read the labels.

## Solution

Replace the universal breathing animation with a distinct motion per activity state. Each state gets its own repeating `SKAction` sequence on `bodySprite`, keyed as `"stateAnim"`. Switching states replaces the animation automatically via SpriteKit's `withKey:` mechanism.

## File Changed

`Glimpse/CharacterNode.swift`

## Animation Map

All animations are subtle and ambient — small motions that register subconsciously without competing for attention.

### `.thinking` — Gentle Sway

Slow side-to-side rotation, like pondering.

```swift
let sway = SKAction.sequence([
    .rotate(toAngle: -0.035, duration: 1.2),  // ~2°
    .rotate(toAngle: 0.035, duration: 1.2)
])
// timingMode: .easeInEaseOut on each action
// 2.4s cycle
```

### `.running` — Quick Bounce

Fast vertical hop, like jogging in place.

```swift
let bounce = SKAction.sequence([
    .moveBy(x: 0, y: -6, duration: 0.25),
    .moveBy(x: 0, y: 6, duration: 0.25)
])
// timingMode: .easeInEaseOut on each action
// 0.5s cycle
```

### `.writing` — Tiny Horizontal Jitter

Rapid micro-tremor, like typing vibration. Linear timing (no easing) for mechanical feel.

```swift
let jitter = SKAction.sequence([
    .moveBy(x: -1, y: 0, duration: 0.06),
    .moveBy(x: 1, y: 0, duration: 0.06)
])
// timingMode: .linear
// 0.12s cycle
```

### `.reading` — Slow Calm Breathe

Gentle vertical scale, calm and focused. Closest to the old default breathing.

```swift
let breathe = SKAction.sequence([
    .scaleY(to: 1.03, duration: 1.0),
    .scaleY(to: 1.0, duration: 1.0)
])
// timingMode: .easeInEaseOut on each action
// 2.0s cycle
```

### `.spawning` — Pulse Scale

Uniform scale pulse, like gathering energy to spawn.

```swift
let pulse = SKAction.sequence([
    .scale(to: 1.06, duration: 0.6),
    .scale(to: 1.0, duration: 0.6)
])
// timingMode: .easeInEaseOut on each action
// 1.2s cycle
```

### `.searching` — Horizontal Scan

Slow side-to-side drift, like scanning left and right.

```swift
let scan = SKAction.sequence([
    .moveBy(x: -3, y: 0, duration: 0.8),
    .moveBy(x: 3, y: 0, duration: 0.8)
])
// timingMode: .easeInEaseOut on each action
// 1.6s cycle
```

### `.sleeping` — Very Slow Breathe + Tiny Bob

Minimal motion — barely alive. Combines a very gentle Y-scale with a tiny vertical drift.

```swift
let up = SKAction.group([
    .scaleY(to: 1.02, duration: 1.8),
    .moveBy(x: 0, y: 1, duration: 1.8)
])
let down = SKAction.group([
    .scaleY(to: 1.0, duration: 1.8),
    .moveBy(x: 0, y: -1, duration: 1.8)
])
let slowBreathe = SKAction.sequence([up, down])
// timingMode: .easeInEaseOut on each action in each group
// 3.6s cycle
```

### `.done` — Same as Sleeping

Done agents are idle. Same animation as `.sleeping`.

### `.asking` — Quick Wiggle

Rapid multi-step rotation, like trying to get attention. Complements the orange glow from the previous feature.

```swift
let wiggle = SKAction.sequence([
    .rotate(toAngle: -0.052, duration: 0.125),  // ~3°
    .rotate(toAngle: 0.052, duration: 0.125),
    .rotate(toAngle: -0.035, duration: 0.125),   // ~2°
    .rotate(toAngle: 0.035, duration: 0.125),
    .rotate(toAngle: 0, duration: 0.125),
    .wait(forDuration: 0.375)  // pause before repeating
])
// timingMode: .easeInEaseOut on each rotate action
// 1.0s cycle
```

## Architecture

### New Method: `startStateAnimation(_ activity:)`

Builds the correct `SKAction` for the given activity, wraps it in `.repeatForever()`, and runs it on `bodySprite` with key `"stateAnim"`.

```swift
private func startStateAnimation(_ activity: SessionMonitor.Activity) {
    // 1. Build the one-cycle action for this state
    // 2. Set timingMode on each sub-action
    // 3. bodySprite.run(.repeatForever(cycle), withKey: "stateAnim")
}
```

Running with `withKey: "stateAnim"` automatically replaces any existing animation with that key — no explicit stop needed between state transitions.

### Reset on Transition

Before starting a new state animation, reset `bodySprite` transform to identity to prevent drift from interrupted animations:

```swift
bodySprite.removeAction(forKey: "stateAnim")
bodySprite.xScale = 1.0
bodySprite.yScale = 1.0
bodySprite.zRotation = 0
bodySprite.position = .zero
```

This goes at the top of `startStateAnimation()` before running the new action.

### Removed: `startBreathing()` and `stopBreathing()`

`startBreathing()` is replaced by `startStateAnimation(.sleeping)`. The action keys change from `"breathing"` + `"bobbing"` to the single `"stateAnim"` key.

`stopBreathing()` is renamed to `stopStateAnimation()` which removes the `"stateAnim"` action and resets bodySprite transform to identity.

### Call Sites

- **`animateAppear()`**: Replace `startBreathing()` with `startStateAnimation(.sleeping)` (initial state)
- **`animateDisappear()`**: Replace `stopBreathing()` with `stopStateAnimation()`
- **`updateActivity()`**: Add `startStateAnimation(activity)` call after the emoji crossfade and glow logic

### Rescale Interaction

`rescale(to:)` calls `bodySprite.setScale(s)`, which sets both xScale and yScale. Since `SKAction.scaleY(to: 1.03)` sets absolute values, it would override the rescale's yScale. The fix: `rescale(to:)` also calls `startStateAnimation(currentActivity)` to restart the animation from the new base scale. The animation snaps to the new scale on the next cycle start, which is imperceptible since rescale events only happen when sessions are added/removed.

## Scope

- **Files changed:** `CharacterNode.swift` only
- **Methods added:** `startStateAnimation(_:)`
- **Methods renamed:** `stopBreathing()` → `stopStateAnimation()`
- **Methods removed:** `startBreathing()`
- **No new dependencies**
- **No API changes**

## Edge Cases

- **Rapid state changes:** Running a new SKAction `withKey:` replaces the previous one atomically. Transform reset at the top of `startStateAnimation()` prevents accumulated drift.
- **Node removed during animation:** SKActions are cleaned up automatically when the node is removed from the scene.
- **Rescale during animation:** `rescale(to:)` restarts the state animation, snapping to the new base scale on the next cycle.
- **`.asking` wiggle + glow interaction:** The wiggle rotation and the glow pulse scale are on different properties (zRotation vs alpha/scale on glowNode) and don't conflict.
- **Session appears directly in non-sleeping state:** `animateAppear()` starts with `.sleeping`, then `handleSessionUpdate()` immediately calls `updateActivity()` which triggers `startStateAnimation()` with the correct state.
