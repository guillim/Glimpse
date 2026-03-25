# Agent Monitor Performance Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate redundant sprite generation and replace Timer-based gaze logic with SKActions in the agent monitor theme.

**Architecture:** Two independent fixes — (1) static `NSCache` in `CharacterGenerator` keyed on `sessionID:roundedSize`, (2) replace three `Timer?` properties in `CharacterNode` with named `SKAction` sequences using action keys for cancellation.

**Tech Stack:** Swift, SpriteKit, Foundation (`NSCache`)

**Spec:** `docs/superpowers/specs/2026-03-25-agent-monitor-performance-design.md`

---

### Task 1: Add sprite cache to CharacterGenerator

**Files:**
- Modify: `Glimpse/CharacterGenerator.swift` — insert after line 7, before the `Traits` struct (add cache + wrapper inside enum)
- Modify: `Glimpse/CharacterGenerator.swift:93-320` (wrap `generate()` with cache lookup)

- [ ] **Step 1: Add CGImageBox wrapper and static cache**

Add these inside the `CharacterGenerator` enum, before the `Traits` struct:

```swift
/// Wraps CGImage for NSCache (requires AnyObject-conforming values).
private class CGImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// Cache of generated sprites keyed on "sessionID:roundedSize".
private static let cache = NSCache<NSString, CGImageBox>()
```

- [ ] **Step 2: Add cache lookup and store to `generate()`**

Replace the `return image` and closing brace (lines 319-320) with cache-store-and-return, and add cache lookup at the top of the method (after line 93):

```swift
static func generate(sessionID: String, size: CGFloat) -> CGImage? {
    let cacheKey = "\(sessionID):\(Int(size.rounded()))" as NSString
    if let cached = cache.object(forKey: cacheKey) {
        return cached.image
    }

    // --- existing generation code (unchanged) ---
    let t = traits(for: sessionID)
    // ... all the way through ...
    let image = ctx.makeImage()

    // Store in cache before returning
    if let image = image {
        cache.setObject(CGImageBox(image), forKey: cacheKey)
    }
    return image
}
```

The body between cache lookup and cache store is the existing code from lines 94-318, unchanged.

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -project Glimpse.xcodeproj -scheme Glimpse -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Glimpse/CharacterGenerator.swift
git commit -m "perf: cache generated sprites with NSCache

Key is sessionID:roundedSize. NSCache handles eviction under
memory pressure automatically. No API changes."
```

---

### Task 2: Remove Timer properties and deinit from CharacterNode

**Files:**
- Modify: `Glimpse/CharacterNode.swift:28-31` (remove timer properties + countdownValue)
- Modify: `Glimpse/CharacterNode.swift:128-132` (remove deinit)

- [ ] **Step 1: Remove Timer properties and countdownValue**

Delete these four lines from the property declarations:

```swift
private var dwellTimer: Timer?
private var activateTimer: Timer?
private var countdownTimer: Timer?
private var countdownValue: Int = 3
```

- [ ] **Step 2: Remove the deinit block**

Delete:

```swift
deinit {
    dwellTimer?.invalidate()
    activateTimer?.invalidate()
    countdownTimer?.invalidate()
}
```

- [ ] **Step 3: Build (expect errors — timer references remain in methods)**

Run: `xcodebuild build -project Glimpse.xcodeproj -scheme Glimpse 2>&1 | grep "error:" | head -10`
Expected: Errors in `gazeEntered`, `gazeExited`, `startCountdown`, `cancelCountdown` referencing removed properties. This confirms we have the right spots to fix next.

---

### Task 3: Replace gazeEntered() with SKActions

**Files:**
- Modify: `Glimpse/CharacterNode.swift` — `gazeEntered()` method (lines 235-249)

- [ ] **Step 1: Replace gazeEntered() body**

Replace the entire `gazeEntered()` method with:

```swift
/// Call when gaze enters this character's hitbox.
func gazeEntered() {
    hasActivated = false
    if !isHelloVisible {
        run(.sequence([
            .wait(forDuration: 0.3),
            .run { [weak self] in self?.showHello() }
        ]), withKey: "dwell")
    }
    // Start 3s timer before showing countdown
    run(.sequence([
        .wait(forDuration: 3.0),
        .run { [weak self] in
            guard let self = self, !self.hasActivated else { return }
            self.startCountdown()
        }
    ]), withKey: "activate")
}
```

---

### Task 4: Replace gazeExited() with SKAction cancellation

**Files:**
- Modify: `Glimpse/CharacterNode.swift` — `gazeExited()` method (lines 252-260)

- [ ] **Step 1: Replace gazeExited() body**

Replace the entire `gazeExited()` method with:

```swift
/// Call when gaze leaves this character's hitbox.
func gazeExited() {
    removeAction(forKey: "dwell")
    removeAction(forKey: "activate")
    cancelCountdown()
    hasActivated = false
    hideHello()
}
```

---

### Task 5: Replace startCountdown() with SKAction sequence

**Files:**
- Modify: `Glimpse/CharacterNode.swift` — `startCountdown()` method (lines 286-311)

- [ ] **Step 1: Replace startCountdown() body**

Replace the entire `startCountdown()` method with:

```swift
/// Start the 3-2-1 countdown using an SKAction sequence.
private func startCountdown() {
    guard !isCountingDown else { return }
    isCountingDown = true

    run(.sequence([
        .run { [weak self] in self?.showCountdownText(3) },
        .wait(forDuration: 1.0),
        .run { [weak self] in self?.showCountdownText(2) },
        .wait(forDuration: 1.0),
        .run { [weak self] in self?.showCountdownText(1) },
        .wait(forDuration: 1.0),
        .run { [weak self] in self?.finishCountdown() }
    ]), withKey: "countdown")
}
```

- [ ] **Step 2: Add finishCountdown() method**

Add this new method right after `startCountdown()`:

```swift
/// Called when countdown reaches zero.
private func finishCountdown() {
    isCountingDown = false
    hasActivated = true
    onActivate?()
    // Restore the log bubble after redirect
    run(.sequence([
        .wait(forDuration: 0.5),
        .run { [weak self] in
            guard let self = self, self.isHelloVisible else { return }
            self.updateBubbleText(self.lastOutput)
        }
    ]))
}
```

---

### Task 6: Refactor showCountdownText() and cancelCountdown()

**Files:**
- Modify: `Glimpse/CharacterNode.swift` — `showCountdownText()` (line 313) and `cancelCountdown()` (lines 323-333)

- [ ] **Step 1: Refactor showCountdownText to accept Int parameter**

Replace:

```swift
private func showCountdownText() {
    let msg = "Redirecting to this agent in \(countdownValue)..."
```

With:

```swift
private func showCountdownText(_ value: Int) {
    let msg = "Redirecting to this agent in \(value)..."
```

The rest of the method body (lines 315-319) stays the same.

- [ ] **Step 2: Replace cancelCountdown() body**

Replace the entire `cancelCountdown()` method with:

```swift
/// Cancel the countdown and restore the log bubble.
private func cancelCountdown() {
    guard isCountingDown else { return }
    removeAction(forKey: "countdown")
    isCountingDown = false
    // Restore bubble style
    helloText.fontColor = .init(red: 0.85, green: 0.95, blue: 0.85, alpha: 1)
    if isHelloVisible {
        updateBubbleText(lastOutput)
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -project Glimpse.xcodeproj -scheme Glimpse -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Glimpse/CharacterNode.swift
git commit -m "perf: replace Timer objects with SKAction sequences

Remove dwellTimer, activateTimer, countdownTimer properties.
Use named SKAction sequences (dwell, activate, countdown keys)
that run within SpriteKit's rendering loop. Eliminates up to
30 main run loop timers with 10 active sessions."
```

---

### Task 7: Manual smoke test

- [ ] **Step 1: Launch the app**

Run: Open `Glimpse.xcodeproj` in Xcode, build and run (Cmd+R).

- [ ] **Step 2: Verify sprite caching**

Start 2+ Claude Code sessions. Characters should appear as before. Observe in Xcode's Debug Navigator that CPU usage does not spike on every 2-second poll cycle.

- [ ] **Step 3: Verify gaze interaction**

Move your head to gaze at a character:
- Hello bubble should appear after ~0.3s (dwell)
- After ~3s sustained gaze, countdown should start (3, 2, 1)
- Look away during countdown — it should cancel and restore the bubble
- Look back — countdown should restart from 3

- [ ] **Step 4: Verify session departure**

Kill a Claude Code session. The character should show "Goodbye!" and fade out normally.
