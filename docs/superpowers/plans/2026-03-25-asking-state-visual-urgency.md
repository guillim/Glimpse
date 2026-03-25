# Asking State Visual Urgency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `.asking` activity state visually urgent with a pulsing orange glow, and add card backgrounds behind all characters for a cleaner layout.

**Architecture:** Two additions to `CharacterNode` — (1) an `SKShapeNode` rounded-rect card behind every character at z:-2, (2) an `SKShapeNode` circle glow at z:-1 that appears only during `.asking` with a repeating pulse animation. `updateActivity()` manages glow lifecycle and card/label color transitions.

**Tech Stack:** Swift, SpriteKit (`SKShapeNode`, `SKAction`)

**Spec:** `docs/superpowers/specs/2026-03-25-asking-state-visual-urgency-design.md`

---

### Task 1: Add card background behind every character

**Files:**
- Modify: `Glimpse/CharacterNode.swift:11` (add `cardBG` property)
- Modify: `Glimpse/CharacterNode.swift:37-120` (create card in `init`, add as child)
- Modify: `Glimpse/CharacterNode.swift:387-394` (rescale card in `rescale(to:)`)

- [ ] **Step 1: Add cardBG property**

Add after line 11 (`private let bodySprite: SKSpriteNode`):

```swift
private let cardBG: SKShapeNode
```

- [ ] **Step 2: Create card in init**

Add after line 51 (`bodySprite = SKSpriteNode(...)`) and before line 53 (`// Status icon label`):

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

- [ ] **Step 3: Add card as first child**

Replace line 114 (`addChild(bodySprite)`) with:

```swift
addChild(cardBG)
addChild(bodySprite)
```

- [ ] **Step 4: Rescale card in rescale(to:)**

Add `cardBG.setScale(s)` to `rescale(to:)`. Replace lines 388-393:

```swift
let s = newSize / characterSize
cardBG.setScale(s)
bodySprite.setScale(s)
statusLabel.setScale(s)
activityWordLabel.setScale(s)
projectLabel.setScale(s)
topicLabel.setScale(s)
```

- [ ] **Step 5: Build and verify**

Run: `xcodebuild build -project Glimpse.xcodeproj -scheme Glimpse -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Glimpse/CharacterNode.swift
git commit -m "feat: add card background behind agent monitor characters

Dark rounded-rect SKShapeNode at z:-2 behind each character.
Sized at 1.6x × 1.8x character size with subtle gray border."
```

---

### Task 2: Add glowNode property and asking state glow helpers

**Files:**
- Modify: `Glimpse/CharacterNode.swift:12` (add `glowNode` property after `cardBG`)
- Modify: `Glimpse/CharacterNode.swift` (add `showAskingGlow()` and `hideAskingGlow()` methods before `// MARK: - Lifecycle Animations`)

- [ ] **Step 1: Add glowNode property**

Add after the `cardBG` property line:

```swift
private var glowNode: SKShapeNode?
```

- [ ] **Step 2: Add showAskingGlow() method**

Add before the `// MARK: - Lifecycle Animations` comment:

```swift
// MARK: - Asking State Glow

private func showAskingGlow() {
    guard glowNode == nil else { return }
    let glow = SKShapeNode(circleOfRadius: characterSize * 0.55)
    glow.fillColor = .clear
    glow.strokeColor = .init(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.7)
    glow.lineWidth = 3
    glow.glowWidth = 8
    glow.zPosition = -1
    glow.alpha = 0
    addChild(glow)
    glowNode = glow

    // Fade in, then start pulsing
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
    let pulse = SKAction.repeatForever(.sequence([grow, shrink]))

    glow.run(.sequence([
        .fadeIn(withDuration: 0.3),
        pulse
    ]), withKey: "askingGlow")

    // Card border to orange
    cardBG.strokeColor = .init(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.6)
}
```

- [ ] **Step 3: Add hideAskingGlow() method**

Add immediately after `showAskingGlow()`:

```swift
private func hideAskingGlow() {
    guard let glow = glowNode else { return }
    glow.removeAction(forKey: "askingGlow")
    glow.run(.sequence([
        .fadeOut(withDuration: 0.3),
        .run { [weak self] in
            glow.removeFromParent()
            self?.glowNode = nil
        }
    ]))
    // Restore card border to default gray
    cardBG.strokeColor = .init(red: 0.3, green: 0.3, blue: 0.4, alpha: 0.4)
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -project Glimpse.xcodeproj -scheme Glimpse -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Glimpse/CharacterNode.swift
git commit -m "feat: add asking glow helper methods

showAskingGlow() creates pulsing orange SKShapeNode circle at z:-1.
hideAskingGlow() fades out and removes. Card border toggles orange/gray."
```

---

### Task 3: Wire glow and label color into updateActivity()

**Files:**
- Modify: `Glimpse/CharacterNode.swift` — `updateActivity()` method (lines 126-155)
- Modify: `Glimpse/CharacterNode.swift` — `rescale(to:)` method

- [ ] **Step 1: Add glow and label color transitions to updateActivity()**

Replace the `updateActivity()` method (lines 126-155) with:

```swift
func updateActivity(_ activity: SessionMonitor.Activity) {
    guard activity != currentActivity else { return }
    let previousActivity = currentActivity
    currentActivity = activity

    let newEmoji: String
    let newWord: String
    switch activity {
    case .reading:   newEmoji = "📖"; newWord = "read"
    case .writing:   newEmoji = "✏️"; newWord = "write"
    case .running:   newEmoji = "⚡"; newWord = "run"
    case .thinking:  newEmoji = "🧠"; newWord = "think"
    case .spawning:  newEmoji = "🐣"; newWord = "spawn"
    case .searching: newEmoji = "🔍"; newWord = "search"
    case .asking:    newEmoji = "❓"; newWord = idleDurationText.map { "ask \($0)" } ?? "ask"
    case .done:      newEmoji = "✅"; newWord = idleDurationText.map { "done \($0)" } ?? "done"
    case .sleeping:  newEmoji = "💤"; newWord = idleDurationText ?? "idle"
    }

    // Crossfade the status icon and word
    statusLabel.run(.sequence([
        .fadeOut(withDuration: 0.15),
        .run { [weak self] in self?.statusLabel.text = newEmoji },
        .fadeIn(withDuration: 0.15)
    ]))
    activityWordLabel.run(.sequence([
        .fadeOut(withDuration: 0.15),
        .run { [weak self] in self?.activityWordLabel.text = newWord },
        .fadeIn(withDuration: 0.15)
    ]))

    // Asking state glow transitions
    if activity == .asking && previousActivity != .asking {
        showAskingGlow()
        activityWordLabel.fontColor = .init(red: 1.0, green: 0.55, blue: 0.0, alpha: 1)
    } else if activity != .asking && previousActivity == .asking {
        hideAskingGlow()
        activityWordLabel.fontColor = .init(white: 0.6, alpha: 1)
    }
}
```

- [ ] **Step 2: Add glowNode to rescale(to:)**

Replace the `rescale(to:)` method with:

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

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -project Glimpse.xcodeproj -scheme Glimpse -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Glimpse/CharacterNode.swift
git commit -m "feat: wire asking glow into activity state transitions

updateActivity() now calls showAskingGlow/hideAskingGlow on .asking
enter/exit. Activity word label turns orange during .asking state."
```

---

### Task 4: Manual smoke test

- [ ] **Step 1: Launch the app**

Open `Glimpse.xcodeproj` in Xcode, build and run (Cmd+R).

- [ ] **Step 2: Verify card backgrounds**

Start 1+ Claude Code sessions. Each character should have a dark rounded-rect card behind it. Cards should scale correctly as sessions are added/removed.

- [ ] **Step 3: Verify asking glow**

In one Claude Code session, trigger a question (e.g. ask Claude something that ends with a question back to you). The character should:
- Show a pulsing orange glow circle behind the sprite
- Card border should turn orange
- "ask" label should be orange
- When you respond (clearing the asking state), glow should fade out over 0.3s, card border and label should revert to gray

- [ ] **Step 4: Verify normal states unaffected**

Characters in `.thinking`, `.running`, `.writing`, etc. should look identical to before — no glow, gray card border, gray label.
