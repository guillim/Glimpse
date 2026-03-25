# Centered Vertical Stack Card Redesign

**Date:** 2026-03-25
**Status:** Approved

## Problem

The current CharacterNode layout has several legibility issues:

1. The status emoji overlaps the character sprite, obscuring the focal point
2. The activity word label is crammed into the top-right corner, tiny and awkward
3. Topic text overflows the card boundaries
4. No clear visual hierarchy — sprite, emoji, and bold topic text all compete for attention
5. Character limbs/accessories clip outside the card

## Solution

Reorganize the card into a clean centered vertical stack: **sprite → emoji + activity word → divider → project → topic**. Nothing overlaps the sprite. The card contains all content with proper padding and text truncation.

## File Changed

`Glimpse/CharacterNode.swift`

## Layout Specification

### Card Dimensions

- Width: `size * 2.0` (wider than current 1.6x to contain text)
- Height: dynamic, but minimum `size * 2.6` to fit all elements
- Background: unchanged — `rgba(0.1, 0.1, 0.15, 0.7)`
- Border: unchanged — `rgba(0.3, 0.3, 0.4, 0.4)`, 1px, cornerRadius 8
- Card position: centered on node origin

### Vertical Layout (top to bottom, all centered horizontally at x: 0)

1. **Body Sprite** — centered in upper portion of card
   - Position: `(0, cardH * 0.2)` approximately — vertically centered in the upper ~60% of the card
   - Size: unchanged (`size × size`)
   - No emoji overlay, no overlapping elements

2. **Status Row** — emoji + activity word on same line
   - Position: below sprite, `y = spriteBottom - 6`
   - Emoji: `fontSize = size * 0.25` (slightly smaller than current 0.3 to fit inline)
   - Activity word: `Menlo-Bold`, `fontSize = max(size * 0.13, 9)`, color `rgba(0.63, 0.63, 0.69, 1)` (brighter than current 0.6)
   - Horizontal layout: emoji left, word right, 4pt gap, both vertically centered
   - Implementation: Use an `SKNode` container with emoji at `x: -(wordWidth/2 + 2)` and word at `x: +(emojiWidth/2 + 2)`, or position both relative to center

3. **Divider** — thin horizontal line
   - Position: below status row, `y = statusRow.y - size * 0.12`
   - Width: `cardWidth * 0.7`
   - Height: 1px
   - Color: `rgba(0.3, 0.3, 0.4, 0.3)` (subtle, same hue as card border but dimmer)
   - Implementation: `SKShapeNode` with a horizontal path

4. **Project Label** — "folder:" prefix + project name
   - Position: below divider, `y = divider.y - size * 0.1`
   - Two separate `SKLabelNode`s positioned inline:
     - `folderPrefixLabel`: "folder:" — `Menlo`, `fontSize = max(size * 0.12, 8)`, color `rgba(0.35, 0.35, 0.42, 1)` (dim hint)
     - `projectLabel`: project name — `Menlo`, same fontSize, color `rgba(0.5, 0.5, 0.56, 1)` (brighter)
   - Both horizontally centered as a pair (prefix left, name right, ~3pt gap)

5. **Topic Label** — up to 3 lines, centered
   - Position: below project label, `y = projectLabel.y - projectLabel.fontSize - 4`
   - Font: `Menlo-Bold`, `fontSize = max(size * 0.13, 9)` (slightly smaller than current 0.15 to fit within card)
   - Color: `rgba(0.7, 0.7, 0.78, 1)`
   - `numberOfLines = 3`
   - `preferredMaxLayoutWidth = cardWidth - 20` (10pt padding each side)
   - Overflow: SpriteKit's `numberOfLines` handles truncation

### Asking State

No changes to the asking glow behavior. The existing `showAskingGlow()` / `hideAskingGlow()` and card border color change work as-is with the new layout. The orange glow circle remains at z:-1 behind the sprite.

The activity word still turns orange during `.asking` state (existing behavior in `updateActivity()`).

## Architecture

### Removed Elements

- `statusLabel` position changes from top-right overlay to centered in status row
- `activityWordLabel` position changes from above-emoji to inline with emoji in status row

### New Elements

- `dividerNode: SKShapeNode` — horizontal line between status row and project info

### Modified Elements

- `cardBG` — wider (2.0x → was 1.6x), taller (2.6x → was 1.8x)
- `statusLabel` — repositioned to status row, slightly smaller fontSize
- `activityWordLabel` — repositioned to status row, inline with emoji
- `projectLabel` — now uses attributed string or two labels for "folder:" prefix styling
- `topicLabel` — `preferredMaxLayoutWidth` clamped to card inner width, slightly smaller fontSize
- `bodySprite` — repositioned to upper portion of card (was at origin)

### Position Calculations

All positions are relative to the node origin (center of card). Using `size` as the character sprite size:

```swift
let cardW = size * 2.0
let cardH = size * 2.6

// Sprite in upper portion
let spriteY = cardH * 0.15
bodySprite.position = CGPoint(x: 0, y: spriteY)

// Status row below sprite
let statusY = spriteY - size * 0.5 - size * 0.15
statusLabel.position = CGPoint(x: -size * 0.15, y: statusY)
activityWordLabel.position = CGPoint(x: size * 0.15, y: statusY)

// Divider
let dividerY = statusY - size * 0.12
// draw line from (-cardW*0.35, dividerY) to (cardW*0.35, dividerY)

// Project label
let projectY = dividerY - size * 0.12

// Topic label
let topicY = projectY - projectLabel.fontSize - 4
```

### Call Site Changes

- `rescale(to:)` — add `dividerNode.setScale(s)`
- `helloBubble` position — adjust Y to account for new sprite position
- No changes to `updateActivity()`, `animateAppear()`, `animateDisappear()`, or glow methods (they operate on existing nodes)

## Scope

- **Files changed:** `CharacterNode.swift` only
- **Properties added:** `dividerNode`
- **Properties modified:** `cardBG`, `bodySprite`, `statusLabel`, `activityWordLabel`, `projectLabel`, `topicLabel` (positions and sizing)
- **No new dependencies**
- **No API changes** — all public methods unchanged

## Edge Cases

- **Long project names:** The project label shares the card's inner width. Names longer than ~12 chars at this font size will need truncation. Use `preferredMaxLayoutWidth` on the project label or truncate the `projectName` string to ~15 chars with "..." suffix in init.
- **Empty topic:** When no topic is set, the card has empty space at the bottom. This is fine — the card height is fixed, and the space reads as "nothing happening yet."
- **Rescale interaction:** All child nodes are individually rescaled in `rescale(to:)`. The new dividerNode needs to be included.
- **Asking glow circle position:** The glow node must be repositioned to match the new sprite Y position (`spriteY`). Set `glow.position = bodySprite.position` in `showAskingGlow()`.
