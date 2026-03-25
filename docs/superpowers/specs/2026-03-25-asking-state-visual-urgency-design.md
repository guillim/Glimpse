# Asking State Visual Urgency + Character Cards

**Date:** 2026-03-25
**Status:** Approved

## Problem

The `.asking` activity state (agent waiting for user input) is visually indistinguishable from other states. It uses the same rendering pattern as every other activity — an emoji swap (❓) and a text label ("ask"). There is no color change, no animation change, and no urgency signal. Users cannot tell at a glance that an agent needs their attention.

## Solution

Two changes to `CharacterNode`:

1. **Pulsing orange glow** around characters in the `.asking` state — a radiating beacon that catches peripheral vision.
2. **Card background** behind every character — a dark rounded rect that gives the grid a cleaner layout and provides a surface for the `.asking` border highlight.

## Fix 1: Card Background Behind Every Character

### File Changed

`Glimpse/CharacterNode.swift`

### Design

Add an `SKShapeNode` rounded rect behind each character, drawn at the lowest z-order. This card contains the sprite, status icon, and labels visually.

#### Properties

```swift
private let cardBG: SKShapeNode
```

#### Sizing

- Width: `characterSize * 1.6`
- Height: `characterSize * 1.8`
- Corner radius: 8

#### Default Style (Non-Asking States)

- Fill: `rgba(0.1, 0.1, 0.15, 0.7)` — dark, semi-transparent
- Stroke: `rgba(0.3, 0.3, 0.4, 0.4)` — subtle gray border
- Line width: 1

#### Asking Style

- Stroke shifts to orange: `rgba(1.0, 0.55, 0.0, 0.6)`
- Fill unchanged (the glow provides the warmth)

#### Z-Order

Card sits at `zPosition = -2`, below all other children. The existing body sprite, labels, and bubble remain at their current z-positions (0 and above).

#### Rescaling

`rescale(to:)` applies the same scale factor to `cardBG`.

## Fix 2: Pulsing Orange Glow for `.asking`

### File Changed

`Glimpse/CharacterNode.swift`

### Design

When a character enters the `.asking` state, an orange glow circle appears behind the body sprite and pulses. When it leaves `.asking`, the glow fades out and is removed.

#### Properties

```swift
private var glowNode: SKShapeNode?
```

`glowNode` is `nil` when not in `.asking` state. Created on demand, removed on state exit.

#### Glow Shape

- `SKShapeNode(circleOfRadius: characterSize * 0.55)`
- Fill: `.clear`
- Stroke: `rgba(1.0, 0.55, 0.0, 0.7)` — warm orange
- Line width: 3
- `glowWidth`: 8 (SpriteKit's built-in Gaussian glow on `SKShapeNode.strokeColor`)
- `zPosition`: -1 (between card at -2 and body sprite at 0)

#### Pulse Animation

Repeating `SKAction` sequence with key `"askingGlow"`:

```
let grow = SKAction.group([
    .scale(to: 1.15, duration: 0.6),
    .fadeAlpha(to: 1.0, duration: 0.6)
])
grow.timingMode = .easeInEaseOut

let shrink = SKAction.group([
    .scale(to: 1.0, duration: 0.6),
    .fadeAlpha(to: 0.7, duration: 0.6)
])
shrink.timingMode = .easeInEaseOut

SKAction.sequence([grow, shrink])
```

Run with `.repeatForever()` and key `"askingGlow"`.

#### State Transitions in `updateActivity()`

**Entering `.asking`:**
1. Create `glowNode` with the shape described above
2. Set initial alpha to 0
3. Add as child at `zPosition = -1`
4. Fade in over 0.3s, then start pulse action
5. Set `cardBG.strokeColor` to orange
6. Set `activityWordLabel.fontColor` to orange `rgb(1.0, 0.55, 0.0)`

**Leaving `.asking`:**
1. Remove action for key `"askingGlow"` on `glowNode`
2. Fade `glowNode` out over 0.3s, then remove from parent and set to `nil`
3. Restore `cardBG.strokeColor` to default gray
4. Restore `activityWordLabel.fontColor` to default gray `rgb(0.6, 0.6, 0.6)`

#### Rescaling

`rescale(to:)` applies the same scale factor to `glowNode` if non-nil.

## Activity Word Label Color

The `activityWordLabel.fontColor` changes to orange `rgb(1.0, 0.55, 0.0)` when in `.asking` state and reverts to gray `rgb(0.6, 0.6, 0.6)` for all other states. This is handled inside `updateActivity()` alongside the glow logic.

## Scope

- **Files changed:** `CharacterNode.swift` only
- **No changes to:** `PokemonScene.swift`, `SessionMonitor.swift`, `CharacterGenerator.swift`
- **No new dependencies:** Uses `SKShapeNode` and `SKAction`, both already in use
- **No API changes:** `CharacterNode` public interface is unchanged
- **Visual behavior:** All other states render identically to before; only `.asking` gains the glow + card highlight

## Edge Cases

- **Multiple agents asking simultaneously:** Each gets its own independent glow — intentionally "loud" to match the urgency goal
- **Rapid state flicker (asking → thinking → asking):** Leaving `.asking` fades out the glow over 0.3s; re-entering creates a fresh glow node. The 0.3s fade prevents visual popping
- **Node removed while asking:** SKActions are cleaned up with the node; `glowNode` is a child so it's removed too
- **Rescale while asking:** `rescale(to:)` handles `glowNode` and `cardBG` alongside existing children
- **Card + glow overlap at small sizes:** At minimum character size (48px), card is 77x86 and glow radius is 26 — both still visible and distinct
