# Centered Vertical Stack Card Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize CharacterNode layout into a clean centered vertical stack (sprite → emoji+word → divider → folder:project → topic) so nothing overlaps the sprite and all text is contained within the card.

**Architecture:** Single-file change to `Glimpse/CharacterNode.swift`. The init method is rewritten to use new card dimensions (2.0x × 2.6x), centered vertical positioning, a new divider node, and a split project label ("folder:" prefix + name). Dependent methods (glow, rescale, helloBubble) are updated for the new sprite position.

**Tech Stack:** Swift, SpriteKit (`SKShapeNode`, `SKLabelNode`, `SKSpriteNode`)

**Spec:** `docs/superpowers/specs/2026-03-25-centered-vertical-stack-design.md`

---

### Task 1: Reorganize card layout — properties and init

**Files:**
- Modify: `Glimpse/CharacterNode.swift:11-125`

- [ ] **Step 1: Add new properties**

Replace lines 14-17:

```swift
    private let statusLabel: SKLabelNode
    private let activityWordLabel: SKLabelNode
    private let projectLabel: SKLabelNode
    private let topicLabel: SKLabelNode
```

with:

```swift
    private let statusLabel: SKLabelNode
    private let activityWordLabel: SKLabelNode
    private let dividerNode: SKShapeNode
    private let folderPrefixLabel: SKLabelNode
    private let projectLabel: SKLabelNode
    private let topicLabel: SKLabelNode
```

- [ ] **Step 2: Rewrite card dimensions and sprite position**

Replace lines 47-54 (card background section):

```swift
        // Card background behind character
        let cardW = size * 1.6
        let cardH = size * 1.8
        cardBG = SKShapeNode(rectOf: CGSize(width: cardW, height: cardH), cornerRadius: 8)
        cardBG.fillColor = .init(red: 0.1, green: 0.1, blue: 0.15, alpha: 0.7)
        cardBG.strokeColor = .init(red: 0.3, green: 0.3, blue: 0.4, alpha: 0.4)
        cardBG.lineWidth = 1
        cardBG.zPosition = -2
```

with:

```swift
        // Card background behind character
        let cardW = size * 2.0
        let cardH = size * 2.6
        cardBG = SKShapeNode(rectOf: CGSize(width: cardW, height: cardH), cornerRadius: 8)
        cardBG.fillColor = .init(red: 0.1, green: 0.1, blue: 0.15, alpha: 0.7)
        cardBG.strokeColor = .init(red: 0.3, green: 0.3, blue: 0.4, alpha: 0.4)
        cardBG.lineWidth = 1
        cardBG.zPosition = -2

        // Sprite in upper portion of card
        let spriteY = cardH * 0.15
        bodySprite.position = CGPoint(x: 0, y: spriteY)
```

- [ ] **Step 3: Rewrite status label positioning**

Replace lines 56-61 (status icon label section):

```swift
        // Status icon label (emoji-based for simplicity)
        statusLabel = SKLabelNode(text: "💤")
        statusLabel.fontSize = size * 0.3
        statusLabel.position = CGPoint(x: size * 0.4, y: size * 0.35)
        statusLabel.verticalAlignmentMode = .center
        statusLabel.horizontalAlignmentMode = .center
```

with:

```swift
        // Status row: emoji + activity word centered below sprite
        let statusY = spriteY - size * 0.5 - size * 0.15
        statusLabel = SKLabelNode(text: "💤")
        statusLabel.fontSize = size * 0.25
        statusLabel.position = CGPoint(x: -size * 0.15, y: statusY)
        statusLabel.verticalAlignmentMode = .center
        statusLabel.horizontalAlignmentMode = .center
```

- [ ] **Step 4: Rewrite activity word label positioning**

Replace lines 63-70 (activity word label section):

```swift
        // Activity word label (above the emoji)
        activityWordLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        activityWordLabel.text = "idle"
        activityWordLabel.fontSize = max(size * 0.12, 8)
        activityWordLabel.fontColor = .init(white: 0.6, alpha: 1)
        activityWordLabel.position = CGPoint(x: size * 0.4, y: size * 0.35 + size * 0.2)
        activityWordLabel.verticalAlignmentMode = .center
        activityWordLabel.horizontalAlignmentMode = .center
```

with:

```swift
        activityWordLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        activityWordLabel.text = "idle"
        activityWordLabel.fontSize = max(size * 0.13, 9)
        activityWordLabel.fontColor = .init(red: 0.63, green: 0.63, blue: 0.69, alpha: 1)
        activityWordLabel.position = CGPoint(x: size * 0.15, y: statusY)
        activityWordLabel.verticalAlignmentMode = .center
        activityWordLabel.horizontalAlignmentMode = .left
```

- [ ] **Step 5: Add divider node**

Insert after the activity word label block (after the new `activityWordLabel.horizontalAlignmentMode = .left` line):

```swift

        // Divider line between status row and project info
        let dividerY = statusY - size * 0.18
        let dividerPath = CGMutablePath()
        dividerPath.move(to: CGPoint(x: -cardW * 0.35, y: 0))
        dividerPath.addLine(to: CGPoint(x: cardW * 0.35, y: 0))
        dividerNode = SKShapeNode(path: dividerPath)
        dividerNode.strokeColor = .init(red: 0.3, green: 0.3, blue: 0.4, alpha: 0.3)
        dividerNode.lineWidth = 1
        dividerNode.position = CGPoint(x: 0, y: dividerY)
```

- [ ] **Step 6: Rewrite project label as folder prefix + name**

Replace lines 72-79 (project name label section):

```swift
        // Project name label
        projectLabel = SKLabelNode(fontNamed: "Menlo")
        projectLabel.text = projectName
        projectLabel.fontSize = max(size * 0.14, 9)
        projectLabel.fontColor = .init(white: 0.5, alpha: 1)
        projectLabel.position = CGPoint(x: 0, y: -size * 0.6 - 4)
        projectLabel.verticalAlignmentMode = .top
        projectLabel.horizontalAlignmentMode = .center
```

with:

```swift
        // Project label: "folder:" prefix (dim) + project name (brighter)
        let projectFontSize = max(size * 0.12, 8)
        let projectY = dividerY - size * 0.12

        folderPrefixLabel = SKLabelNode(fontNamed: "Menlo")
        folderPrefixLabel.text = "folder:"
        folderPrefixLabel.fontSize = projectFontSize
        folderPrefixLabel.fontColor = .init(red: 0.35, green: 0.35, blue: 0.42, alpha: 1)
        folderPrefixLabel.verticalAlignmentMode = .center
        folderPrefixLabel.horizontalAlignmentMode = .right

        projectLabel = SKLabelNode(fontNamed: "Menlo")
        let truncatedName = projectName.count > 15
            ? String(projectName.prefix(14)) + "…"
            : projectName
        projectLabel.text = truncatedName
        projectLabel.fontSize = projectFontSize
        projectLabel.fontColor = .init(red: 0.5, green: 0.5, blue: 0.56, alpha: 1)
        projectLabel.verticalAlignmentMode = .center
        projectLabel.horizontalAlignmentMode = .left

        // Position prefix and name as a centered pair with 3pt gap
        let prefixWidth = folderPrefixLabel.frame.width
        let nameWidth = projectLabel.frame.width
        let totalWidth = prefixWidth + 3 + nameWidth
        folderPrefixLabel.position = CGPoint(x: -totalWidth / 2 + prefixWidth, y: projectY)
        projectLabel.position = CGPoint(x: -totalWidth / 2 + prefixWidth + 3, y: projectY)
```

- [ ] **Step 7: Rewrite topic label positioning and width**

Replace lines 81-91 (topic label section):

```swift
        // Topic label (below project label, up to 3 lines)
        topicLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        topicLabel.text = ""
        topicLabel.fontSize = max(size * 0.15, 10)
        topicLabel.fontColor = .init(white: 0.7, alpha: 1)
        topicLabel.numberOfLines = 3
        topicLabel.preferredMaxLayoutWidth = size * 1.5
        let topicY: CGFloat = -size * 0.6 - 4 - projectLabel.fontSize - 2
        topicLabel.position = CGPoint(x: 0, y: topicY)
        topicLabel.verticalAlignmentMode = .top
        topicLabel.horizontalAlignmentMode = .center
```

with:

```swift
        // Topic label (below project label, up to 3 lines)
        topicLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        topicLabel.text = ""
        topicLabel.fontSize = max(size * 0.13, 9)
        topicLabel.fontColor = .init(red: 0.7, green: 0.7, blue: 0.78, alpha: 1)
        topicLabel.numberOfLines = 3
        topicLabel.preferredMaxLayoutWidth = cardW - 20
        let topicY = projectY - projectFontSize - 4
        topicLabel.position = CGPoint(x: 0, y: topicY)
        topicLabel.verticalAlignmentMode = .top
        topicLabel.horizontalAlignmentMode = .center
```

- [ ] **Step 8: Update helloBubble position for new sprite Y**

Replace line 110:

```swift
        helloBubble.position = CGPoint(x: 0, y: size * 0.55 + 12)
```

with:

```swift
        helloBubble.position = CGPoint(x: 0, y: spriteY + size * 0.55 + 12)
```

- [ ] **Step 9: Add dividerNode and folderPrefixLabel to child list**

Replace lines 118-124:

```swift
        addChild(cardBG)
        addChild(bodySprite)
        addChild(statusLabel)
        addChild(activityWordLabel)
        addChild(projectLabel)
        addChild(topicLabel)
        addChild(helloBubble)
```

with:

```swift
        addChild(cardBG)
        addChild(bodySprite)
        addChild(statusLabel)
        addChild(activityWordLabel)
        addChild(dividerNode)
        addChild(folderPrefixLabel)
        addChild(projectLabel)
        addChild(topicLabel)
        addChild(helloBubble)
```

- [ ] **Step 10: Build and verify**

Run: `xcodebuild build -project Glimpse.xcodeproj -scheme Glimpse -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 11: Commit**

```bash
git add Glimpse/CharacterNode.swift
git commit -m "feat: reorganize card into centered vertical stack layout

Sprite centered in upper card, emoji+word row below, divider line,
folder: prefix + project name, topic clamped to card width.
Card widened to 2.0x and heightened to 2.6x character size."
```

---

### Task 2: Update dependent methods for new layout

**Files:**
- Modify: `Glimpse/CharacterNode.swift` — `showAskingGlow()`, `rescale(to:)`, `updateActivity()`

- [ ] **Step 1: Position glow at sprite location in showAskingGlow()**

In `showAskingGlow()`, after line `addChild(glow)` and before `glowNode = glow`, add:

```swift
        glow.position = bodySprite.position
```

The full section should read:

```swift
        glow.alpha = 0
        addChild(glow)
        glow.position = bodySprite.position
        glowNode = glow
```

- [ ] **Step 2: Add new nodes to rescale(to:)**

Replace the `rescale(to:)` method:

```swift
    func rescale(to newSize: CGFloat) {
        let s = newSize / characterSize
        cardBG.setScale(s)
        bodySprite.setScale(s)
        statusLabel.setScale(s)
        activityWordLabel.setScale(s)
        projectLabel.setScale(s)
        topicLabel.setScale(s)
        glowNode?.setScale(s)
    }
```

with:

```swift
    func rescale(to newSize: CGFloat) {
        let s = newSize / characterSize
        cardBG.setScale(s)
        bodySprite.setScale(s)
        statusLabel.setScale(s)
        activityWordLabel.setScale(s)
        dividerNode.setScale(s)
        folderPrefixLabel.setScale(s)
        projectLabel.setScale(s)
        topicLabel.setScale(s)
        glowNode?.setScale(s)
    }
```

- [ ] **Step 3: Update activityWordLabel reset color to match new default**

In `updateActivity()`, replace the color reset for non-asking state:

```swift
                    self?.activityWordLabel.fontColor = .init(white: 0.6, alpha: 1)
```

with:

```swift
                    self?.activityWordLabel.fontColor = .init(red: 0.63, green: 0.63, blue: 0.69, alpha: 1)
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -project Glimpse.xcodeproj -scheme Glimpse -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Glimpse/CharacterNode.swift
git commit -m "fix: update glow position, rescale, and label color for new layout

Glow node positioned at sprite Y offset. Rescale includes dividerNode
and folderPrefixLabel. Activity word default color matches new spec."
```

---

### Task 3: Manual smoke test

- [ ] **Step 1: Launch the app**

Open `Glimpse.xcodeproj` in Xcode, build and run (Cmd+R).

- [ ] **Step 2: Verify card layout**

Start 1+ Claude Code sessions. Each character should show:
- Sprite centered in upper portion of card, face fully visible
- Emoji + activity word on same line below sprite, centered
- Thin divider line
- "folder:" in dim text + project name in slightly brighter text
- Topic text (if present) contained within card, up to 3 lines

- [ ] **Step 3: Verify text containment**

No text should overflow outside the card boundaries. Long topic text should truncate at 3 lines. Long project names (>15 chars) should truncate with "…".

- [ ] **Step 4: Verify asking state glow**

Trigger an asking state. The orange glow should appear centered behind the sprite (not at card center). Card border should turn orange. Activity word should turn orange.

- [ ] **Step 5: Verify rescale**

Add/remove sessions to trigger grid rescaling. All elements (including divider, folder prefix) should scale together without misalignment.
