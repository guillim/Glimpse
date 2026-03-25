# Pokemon Session Monitor Theme — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a SpriteKit-based theme to Glimpse that shows procedurally generated Pokemon-styled characters, one per active Claude Code session, with live status updates and head-tracking gaze interaction.

**Architecture:** New SpriteKit scene (`PokemonScene`) swapped in via `DesktopWindowController` when the Pokemon theme is selected. A `SessionMonitor` polls `~/.claude/` JSONL logs every 5 seconds to discover sessions and classify activity. `CharacterGenerator` produces unique creatures from session IDs via Core Graphics. `CharacterNode` wraps each character's sprite, status icon, label, and hello bubble. HeadTracker is reused with zero changes.

**Tech Stack:** Swift, SpriteKit (SKScene/SKSpriteNode/SKLabelNode), Core Graphics (CGContext), FileManager for log scanning, existing HeadTracker API.

**Spec:** `docs/superpowers/specs/2026-03-25-pokemon-session-monitor-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| **Create:** `Glimpse/CharacterGenerator.swift` | Pure function: sessionID → CGImage. Core Graphics procedural drawing. |
| **Create:** `Glimpse/CharacterNode.swift` | SKNode subclass: body sprite, status icon, label, hello bubble, animations. |
| **Create:** `Glimpse/SessionMonitor.swift` | Timer-based scanner: discovers sessions, parses JSONL, classifies activity. |
| **Create:** `Glimpse/PokemonScene.swift` | SKScene: dark background, adaptive grid, gaze hit-testing, session lifecycle. |
| **Create:** `TODO.md` | Deferred work tracker (Cursor support, etc). |
| **Modify:** `Glimpse/SceneViewController.swift` | Add Pokemon SceneEntry, expose HeadTracker, handle SpriteKit theme flag. |
| **Modify:** `Glimpse/DesktopWindowController.swift` | Support swapping contentView between SCNView and SKView. |
| **Modify:** `Glimpse/AppDelegate.swift` | Pokemon appears in theme menu, keyboard shortcut cycles through it. |

---

### Task 1: CharacterGenerator — Procedural Creature Drawing

**Files:**
- Create: `Glimpse/CharacterGenerator.swift`

This is a pure function with no dependencies on other new files. Can be built and verified in isolation.

- [ ] **Step 1: Create CharacterGenerator.swift with the trait system**

```swift
// Glimpse/CharacterGenerator.swift
import AppKit

/// Generates unique Pokemon-styled pixel art creatures from a session ID seed.
/// Pure function: same sessionID always produces the same CGImage.
enum CharacterGenerator {

    /// All traits derived from a deterministic seed.
    struct Traits {
        enum BodyShape: CaseIterable { case round, oval, squarish, blob }
        enum EyeStyle: CaseIterable { case dot, circle, anime, sleepy }
        enum EarStyle: CaseIterable { case pointy, round, antenna, none }
        enum TailStyle: CaseIterable { case lightning, swirl, flame, none }
        enum MouthStyle: CaseIterable { case smile, open, catMouth, line }
        enum CheekStyle: CaseIterable { case circles, triangles, none }

        let bodyShape: BodyShape
        let bodyColor: NSColor
        let accentColor: NSColor
        let eyeStyle: EyeStyle
        let earStyle: EarStyle
        let tailStyle: TailStyle
        let mouthStyle: MouthStyle
        let cheekStyle: CheekStyle
    }

    /// Pokemon-inspired color palette.
    private static let bodyColors: [NSColor] = [
        NSColor(red: 1.0,  green: 0.8,  blue: 0.02, alpha: 1), // Pikachu yellow
        NSColor(red: 0.93, green: 0.30, blue: 0.22, alpha: 1), // Charmander red
        NSColor(red: 0.30, green: 0.69, blue: 0.93, alpha: 1), // Squirtle blue
        NSColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1), // Bulbasaur green
        NSColor(red: 0.65, green: 0.45, blue: 0.85, alpha: 1), // Gengar purple
        NSColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1), // Charizard orange
        NSColor(red: 0.95, green: 0.55, blue: 0.65, alpha: 1), // Jigglypuff pink
        NSColor(red: 0.30, green: 0.78, blue: 0.75, alpha: 1), // Teal
        NSColor(red: 0.60, green: 0.45, blue: 0.30, alpha: 1), // Eevee brown
    ]

    /// Accent colors — lighter variants for belly patches and ear tips.
    private static let accentColors: [NSColor] = [
        NSColor(red: 1.0,  green: 0.95, blue: 0.7,  alpha: 1), // cream
        NSColor(red: 1.0,  green: 0.75, blue: 0.7,  alpha: 1), // light pink
        NSColor(red: 0.75, green: 0.88, blue: 1.0,  alpha: 1), // light blue
        NSColor(red: 0.75, green: 0.95, blue: 0.8,  alpha: 1), // light green
        NSColor(red: 0.85, green: 0.78, blue: 0.95, alpha: 1), // lavender
        NSColor(red: 1.0,  green: 0.85, blue: 0.65, alpha: 1), // peach
        NSColor(red: 1.0,  green: 0.82, blue: 0.86, alpha: 1), // blush
        NSColor(red: 0.78, green: 0.95, blue: 0.93, alpha: 1), // mint
        NSColor(red: 0.85, green: 0.75, blue: 0.65, alpha: 1), // tan
    ]

    /// Deterministic seeded RNG from a session ID string.
    private static func seed(from sessionID: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in sessionID.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return hash
    }

    /// Pick a random element from a CaseIterable using a mutable seed.
    private static func pick<T: CaseIterable>(_ seed: inout UInt64) -> T {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let all = Array(T.allCases)
        return all[Int(seed >> 33) % all.count]
    }

    /// Pick an index in a range using a mutable seed.
    private static func pickIndex(_ seed: inout UInt64, count: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int(seed >> 33) % count
    }

    /// Derive all traits from a session ID.
    static func traits(for sessionID: String) -> Traits {
        var s = seed(from: sessionID)
        let bodyIdx = pickIndex(&s, count: bodyColors.count)
        return Traits(
            bodyShape:  pick(&s),
            bodyColor:  bodyColors[bodyIdx],
            accentColor: accentColors[bodyIdx],
            eyeStyle:   pick(&s),
            earStyle:   pick(&s),
            tailStyle:  pick(&s),
            mouthStyle: pick(&s),
            cheekStyle: pick(&s)
        )
    }

    /// Generate a character image at the given pixel size.
    static func generate(sessionID: String, size: CGFloat) -> CGImage? {
        let t = traits(for: sessionID)
        let s = size
        let scale: CGFloat = 2.0  // retina

        guard let ctx = CGContext(
            data: nil,
            width: Int(s * scale),
            height: Int(s * scale),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)

        // All drawing is relative to the size
        let cx = s / 2      // center x
        let cy = s / 2      // center y
        let bodyW: CGFloat  // body width
        let bodyH: CGFloat  // body height

        switch t.bodyShape {
        case .round:
            bodyW = s * 0.55; bodyH = s * 0.55
        case .oval:
            bodyW = s * 0.5;  bodyH = s * 0.6
        case .squarish:
            bodyW = s * 0.55; bodyH = s * 0.5
        case .blob:
            bodyW = s * 0.6;  bodyH = s * 0.55
        }

        let bodyRect = CGRect(x: cx - bodyW/2, y: cy - bodyH/2 - s*0.02, width: bodyW, height: bodyH)

        // 1. Body fill
        ctx.setFillColor(t.bodyColor.cgColor)
        switch t.bodyShape {
        case .round:
            ctx.fillEllipse(in: bodyRect)
        case .oval:
            ctx.fillEllipse(in: bodyRect)
        case .squarish:
            let path = CGPath(roundedRect: bodyRect, cornerWidth: bodyW * 0.25, cornerHeight: bodyH * 0.25, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()
        case .blob:
            ctx.fillEllipse(in: bodyRect.insetBy(dx: -s*0.02, dy: s*0.02))
        }

        // 2. Accent belly patch
        let bellyRect = CGRect(x: cx - bodyW * 0.3, y: cy - bodyH * 0.25 - s*0.02, width: bodyW * 0.6, height: bodyH * 0.45)
        ctx.setFillColor(t.accentColor.cgColor)
        ctx.fillEllipse(in: bellyRect)

        // 3. Eyes
        let eyeY = cy + bodyH * 0.1
        let eyeSpacing = bodyW * 0.22
        let eyeSize: CGFloat

        switch t.eyeStyle {
        case .dot:
            eyeSize = s * 0.06
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - eyeSpacing - eyeSize/2, y: eyeY - eyeSize/2, width: eyeSize, height: eyeSize))
            ctx.fillEllipse(in: CGRect(x: cx + eyeSpacing - eyeSize/2, y: eyeY - eyeSize/2, width: eyeSize, height: eyeSize))
        case .circle:
            eyeSize = s * 0.09
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - eyeSpacing - eyeSize/2, y: eyeY - eyeSize/2, width: eyeSize, height: eyeSize))
            ctx.fillEllipse(in: CGRect(x: cx + eyeSpacing - eyeSize/2, y: eyeY - eyeSize/2, width: eyeSize, height: eyeSize))
            let pupil = eyeSize * 0.5
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - eyeSpacing - pupil/2, y: eyeY - pupil/2, width: pupil, height: pupil))
            ctx.fillEllipse(in: CGRect(x: cx + eyeSpacing - pupil/2, y: eyeY - pupil/2, width: pupil, height: pupil))
        case .anime:
            eyeSize = s * 0.1
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - eyeSpacing - eyeSize/2, y: eyeY - eyeSize*0.6, width: eyeSize, height: eyeSize * 1.2))
            ctx.fillEllipse(in: CGRect(x: cx + eyeSpacing - eyeSize/2, y: eyeY - eyeSize*0.6, width: eyeSize, height: eyeSize * 1.2))
            // Highlight
            let hl = eyeSize * 0.3
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - eyeSpacing - eyeSize/2 + eyeSize*0.15, y: eyeY + eyeSize*0.15, width: hl, height: hl))
            ctx.fillEllipse(in: CGRect(x: cx + eyeSpacing - eyeSize/2 + eyeSize*0.15, y: eyeY + eyeSize*0.15, width: hl, height: hl))
        case .sleepy:
            eyeSize = s * 0.08
            ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
            ctx.setLineWidth(s * 0.02)
            // Left eye — horizontal arc
            ctx.addArc(center: CGPoint(x: cx - eyeSpacing, y: eyeY), radius: eyeSize/2, startAngle: .pi * 0.1, endAngle: .pi * 0.9, clockwise: false)
            ctx.strokePath()
            // Right eye
            ctx.addArc(center: CGPoint(x: cx + eyeSpacing, y: eyeY), radius: eyeSize/2, startAngle: .pi * 0.1, endAngle: .pi * 0.9, clockwise: false)
            ctx.strokePath()
        }

        // 4. Mouth
        let mouthY = cy - bodyH * 0.08
        ctx.setStrokeColor(CGColor(gray: 0.15, alpha: 1))
        ctx.setLineWidth(s * 0.018)

        switch t.mouthStyle {
        case .smile:
            ctx.addArc(center: CGPoint(x: cx, y: mouthY + s*0.02), radius: bodyW * 0.12, startAngle: .pi * 1.2, endAngle: .pi * 1.8, clockwise: false)
            ctx.strokePath()
        case .open:
            ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: cx - s*0.04, y: mouthY - s*0.03, width: s*0.08, height: s*0.06))
        case .catMouth:
            // W shape
            let mw = bodyW * 0.15
            ctx.move(to: CGPoint(x: cx - mw, y: mouthY))
            ctx.addLine(to: CGPoint(x: cx, y: mouthY - s*0.03))
            ctx.addLine(to: CGPoint(x: cx + mw, y: mouthY))
            ctx.strokePath()
        case .line:
            ctx.move(to: CGPoint(x: cx - bodyW * 0.1, y: mouthY))
            ctx.addLine(to: CGPoint(x: cx + bodyW * 0.1, y: mouthY))
            ctx.strokePath()
        }

        // 5. Ears / horns
        let earY = cy + bodyH/2 - s*0.02
        ctx.setFillColor(t.bodyColor.cgColor)

        switch t.earStyle {
        case .pointy:
            // Left ear
            ctx.move(to: CGPoint(x: cx - bodyW*0.3, y: earY))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.45, y: earY + s*0.2))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.15, y: earY + s*0.05))
            ctx.fillPath()
            // Right ear
            ctx.move(to: CGPoint(x: cx + bodyW*0.3, y: earY))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.45, y: earY + s*0.2))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.15, y: earY + s*0.05))
            ctx.fillPath()
            // Accent tips
            ctx.setFillColor(t.accentColor.cgColor)
            ctx.move(to: CGPoint(x: cx - bodyW*0.38, y: earY + s*0.13))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.45, y: earY + s*0.2))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.3, y: earY + s*0.15))
            ctx.fillPath()
            ctx.move(to: CGPoint(x: cx + bodyW*0.38, y: earY + s*0.13))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.45, y: earY + s*0.2))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.3, y: earY + s*0.15))
            ctx.fillPath()
        case .round:
            ctx.fillEllipse(in: CGRect(x: cx - bodyW*0.45, y: earY - s*0.02, width: s*0.14, height: s*0.16))
            ctx.fillEllipse(in: CGRect(x: cx + bodyW*0.45 - s*0.14, y: earY - s*0.02, width: s*0.14, height: s*0.16))
        case .antenna:
            ctx.setStrokeColor(t.bodyColor.cgColor)
            ctx.setLineWidth(s * 0.025)
            ctx.move(to: CGPoint(x: cx - bodyW*0.15, y: earY + s*0.02))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.2, y: earY + s*0.2))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: cx + bodyW*0.15, y: earY + s*0.02))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.2, y: earY + s*0.2))
            ctx.strokePath()
            // Antenna tips
            ctx.setFillColor(t.accentColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - bodyW*0.2 - s*0.03, y: earY + s*0.17, width: s*0.06, height: s*0.06))
            ctx.fillEllipse(in: CGRect(x: cx + bodyW*0.2 - s*0.03, y: earY + s*0.17, width: s*0.06, height: s*0.06))
        case .none:
            break
        }

        // 6. Tail
        let tailX = cx + bodyW/2 - s*0.02
        let tailY = cy - bodyH * 0.1

        switch t.tailStyle {
        case .lightning:
            ctx.setFillColor(t.bodyColor.cgColor)
            ctx.move(to: CGPoint(x: tailX, y: tailY))
            ctx.addLine(to: CGPoint(x: tailX + s*0.15, y: tailY + s*0.08))
            ctx.addLine(to: CGPoint(x: tailX + s*0.1, y: tailY))
            ctx.addLine(to: CGPoint(x: tailX + s*0.22, y: tailY + s*0.12))
            ctx.addLine(to: CGPoint(x: tailX + s*0.12, y: tailY + s*0.04))
            ctx.addLine(to: CGPoint(x: tailX + s*0.08, y: tailY - s*0.04))
            ctx.fillPath()
        case .swirl:
            ctx.setStrokeColor(t.bodyColor.cgColor)
            ctx.setLineWidth(s * 0.03)
            ctx.addArc(center: CGPoint(x: tailX + s*0.1, y: tailY), radius: s*0.08, startAngle: .pi, endAngle: -.pi * 0.3, clockwise: true)
            ctx.strokePath()
        case .flame:
            ctx.setFillColor(NSColor(red: 1, green: 0.5, blue: 0.1, alpha: 1).cgColor)
            ctx.move(to: CGPoint(x: tailX, y: tailY - s*0.03))
            ctx.addLine(to: CGPoint(x: tailX + s*0.12, y: tailY + s*0.06))
            ctx.addLine(to: CGPoint(x: tailX + s*0.08, y: tailY - s*0.01))
            ctx.addLine(to: CGPoint(x: tailX + s*0.18, y: tailY + s*0.03))
            ctx.addLine(to: CGPoint(x: tailX + s*0.05, y: tailY - s*0.06))
            ctx.fillPath()
        case .none:
            break
        }

        // 7. Cheek marks
        let cheekY = cy - s*0.01
        switch t.cheekStyle {
        case .circles:
            ctx.setFillColor(NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 0.5).cgColor)
            let cr = s * 0.055
            ctx.fillEllipse(in: CGRect(x: cx - bodyW*0.35, y: cheekY - cr, width: cr*2, height: cr*2))
            ctx.fillEllipse(in: CGRect(x: cx + bodyW*0.35 - cr*2, y: cheekY - cr, width: cr*2, height: cr*2))
        case .triangles:
            ctx.setFillColor(NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 0.5).cgColor)
            let ts = s * 0.06
            // Left
            ctx.move(to: CGPoint(x: cx - bodyW*0.32, y: cheekY - ts*0.5))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.32 + ts, y: cheekY - ts*0.5))
            ctx.addLine(to: CGPoint(x: cx - bodyW*0.32 + ts*0.5, y: cheekY + ts*0.5))
            ctx.fillPath()
            // Right
            ctx.move(to: CGPoint(x: cx + bodyW*0.32, y: cheekY - ts*0.5))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.32 - ts, y: cheekY - ts*0.5))
            ctx.addLine(to: CGPoint(x: cx + bodyW*0.32 - ts*0.5, y: cheekY + ts*0.5))
            ctx.fillPath()
        case .none:
            break
        }

        return ctx.makeImage()
    }
}
```

- [ ] **Step 2: Verify it compiles**

Build the Xcode project from the command line or open in Xcode and confirm no errors. The file has no dependencies on other new files.

Run: `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

Note: You'll need to add the file to the Xcode project first. Add `CharacterGenerator.swift` to the Glimpse target in `Glimpse.xcodeproj/project.pbxproj`.

- [ ] **Step 3: Commit**

```bash
git add Glimpse/CharacterGenerator.swift Glimpse.xcodeproj/project.pbxproj
git commit -m "feat: add CharacterGenerator — procedural creature drawing from session ID"
```

---

### Task 2: SessionMonitor — Log Scanning & Activity Detection

**Files:**
- Create: `Glimpse/SessionMonitor.swift`

Independent of CharacterGenerator and CharacterNode. Scans `~/.claude/` for JSONL logs and classifies session activity.

- [ ] **Step 1: Create SessionMonitor.swift**

```swift
// Glimpse/SessionMonitor.swift
import Foundation

/// Monitors active Claude Code sessions by scanning ~/.claude/ JSONL log files.
/// Polls every 5 seconds and notifies a delegate of session changes.
final class SessionMonitor {

    /// Activity state for a single Claude Code session.
    enum Activity: Equatable {
        case reading    // Agent is reading files (Read, Glob, Grep tools)
        case talking    // Agent is outputting a text response
        case waiting    // Session waiting for human input
        case sleeping   // Active but idle
    }

    /// Snapshot of a discovered session.
    struct Session: Equatable {
        let id: String            // JSONL filename (UUID)
        let projectName: String   // Extracted from parent directory name
        let activity: Activity
        let lastModified: Date

        static func == (lhs: Session, rhs: Session) -> Bool {
            lhs.id == rhs.id && lhs.activity == rhs.activity
        }
    }

    /// Called on the main thread when sessions change.
    var onUpdate: (([Session]) -> Void)?

    private var timer: Timer?
    private var previousSessions: [String: Session] = [:]

    /// Base directory for Claude Code projects.
    private let claudeProjectsDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/projects", isDirectory: true)
    }()

    /// Start polling every 5 seconds.
    func start() {
        stop()
        // Fire immediately, then every 5s.
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    /// Stop polling.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One scan cycle: discover sessions, classify activity, notify delegate.
    private func scan() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let sessions = self.discoverSessions()
            DispatchQueue.main.async {
                self.previousSessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
                self.onUpdate?(sessions)
            }
        }
    }

    /// Discover all active sessions across all projects.
    private func discoverSessions() -> [Session] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: claudeProjectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var sessions: [Session] = []
        let now = Date()
        let activeThreshold: TimeInterval = 5 * 60   // 5 minutes

        for dirURL in projectDirs {
            guard (try? dirURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            // Skip "memory" directories
            if dirURL.lastPathComponent == "memory" { continue }

            let projectName = Self.extractProjectName(from: dirURL.lastPathComponent)

            guard let files = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else { continue }

            for fileURL in files {
                guard fileURL.pathExtension == "jsonl" else { continue }

                guard let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = attrs.contentModificationDate else { continue }

                // Only active sessions (modified in last 5 minutes)
                guard now.timeIntervalSince(modified) < activeThreshold else { continue }

                let sessionID = fileURL.deletingPathExtension().lastPathComponent
                let activity = Self.classifyActivity(fileURL: fileURL, lastModified: modified, now: now)

                sessions.append(Session(
                    id: sessionID,
                    projectName: projectName,
                    activity: activity,
                    lastModified: modified
                ))
            }
        }

        return sessions
    }

    /// Extract human-readable project name from encoded directory name.
    /// "-Users-gui-github-background" → "background"
    static func extractProjectName(from dirName: String) -> String {
        let components = dirName.split(separator: "-").map(String.init)
        return components.last ?? dirName
    }

    /// Read last ~10 lines of a JSONL file and classify activity.
    static func classifyActivity(fileURL: URL, lastModified: Date, now: Date) -> Activity {
        // If no activity for 2+ minutes, sleeping
        if now.timeIntervalSince(lastModified) > 120 { return .sleeping }

        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return .sleeping
        }

        // Get last ~10 non-empty lines
        let lines = content.components(separatedBy: .newlines)
            .suffix(15)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(10)

        // Walk backwards to find the most recent meaningful message
        for line in lines.reversed() {
            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String

            // Check for assistant message with tool use (reading)
            if type == "assistant",
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {

                // Check for tool_use blocks — reading tools
                let readingTools: Set<String> = ["Read", "Glob", "Grep"]
                for block in content {
                    if block["type"] as? String == "tool_use",
                       let toolName = block["name"] as? String,
                       readingTools.contains(toolName) {
                        return .reading
                    }
                }

                // Check for text output — talking
                for block in content {
                    if block["type"] as? String == "text" {
                        return .talking
                    }
                }
            }

            // Check for assistant end_turn — waiting for human
            if type == "assistant",
               let message = json["message"] as? [String: Any],
               message["stop_reason"] as? String == "end_turn" {
                // If last modified > 30s ago, waiting for input
                if now.timeIntervalSince(lastModified) > 30 {
                    return .waiting
                }
                return .talking  // just finished talking
            }

            // User message — session is active, agent is probably processing
            if type == "user" {
                return .talking
            }
        }

        return .sleeping
    }
}
```

- [ ] **Step 2: Verify it compiles**

Add the file to Xcode project and build.

Run: `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Glimpse/SessionMonitor.swift Glimpse.xcodeproj/project.pbxproj
git commit -m "feat: add SessionMonitor — polls Claude Code JSONL logs every 5s"
```

---

### Task 3: CharacterNode — Sprite with Status, Label, and Hello Bubble

**Files:**
- Create: `Glimpse/CharacterNode.swift`

Depends on: Task 1 (CharacterGenerator) for the body sprite image.

- [ ] **Step 1: Create CharacterNode.swift**

```swift
// Glimpse/CharacterNode.swift
import SpriteKit

/// A single Pokemon-styled character representing a Claude Code session.
/// Contains: body sprite, status icon, project label, and hello bubble.
final class CharacterNode: SKNode {

    let sessionID: String
    let projectName: String

    private let bodySprite: SKSpriteNode
    private let statusLabel: SKLabelNode
    private let projectLabel: SKLabelNode
    private let helloBubble: SKNode
    private let helloBubbleBG: SKShapeNode
    private let helloText: SKLabelNode

    /// Track current status to avoid redundant updates.
    private(set) var currentActivity: SessionMonitor.Activity = .sleeping

    /// Whether the hello bubble is currently showing.
    private var isHelloVisible = false
    private var dwellTimer: Timer?

    /// The character size (width & height of the body sprite).
    let characterSize: CGFloat

    init(sessionID: String, projectName: String, size: CGFloat) {
        self.sessionID = sessionID
        self.projectName = projectName
        self.characterSize = size

        // Body sprite from procedural generator
        let cgImage = CharacterGenerator.generate(sessionID: sessionID, size: size)
        let texture: SKTexture
        if let img = cgImage {
            texture = SKTexture(cgImage: img)
        } else {
            texture = SKTexture()
        }
        texture.filteringMode = .nearest  // pixel art — no smoothing
        bodySprite = SKSpriteNode(texture: texture, size: CGSize(width: size, height: size))

        // Status icon label (emoji-based for simplicity)
        statusLabel = SKLabelNode(text: "💤")
        statusLabel.fontSize = size * 0.3
        statusLabel.position = CGPoint(x: size * 0.4, y: size * 0.35)
        statusLabel.verticalAlignmentMode = .center
        statusLabel.horizontalAlignmentMode = .center

        // Project name label
        projectLabel = SKLabelNode(fontNamed: "Menlo")
        projectLabel.text = projectName
        projectLabel.fontSize = max(size * 0.16, 10)
        projectLabel.fontColor = .init(white: 0.6, alpha: 1)
        projectLabel.position = CGPoint(x: 0, y: -size * 0.6 - 4)
        projectLabel.verticalAlignmentMode = .top
        projectLabel.horizontalAlignmentMode = .center

        // Hello bubble (hidden by default)
        helloText = SKLabelNode(fontNamed: "Menlo-Bold")
        helloText.text = "Hello!"
        helloText.fontSize = max(size * 0.18, 11)
        helloText.fontColor = .init(white: 0.15, alpha: 1)
        helloText.verticalAlignmentMode = .center
        helloText.horizontalAlignmentMode = .center
        helloText.position = CGPoint(x: 0, y: 0)

        let padding: CGFloat = 8
        let bubbleW = helloText.frame.width + padding * 2
        let bubbleH = helloText.fontSize + padding * 2
        helloBubbleBG = SKShapeNode(rectOf: CGSize(width: bubbleW, height: bubbleH), cornerRadius: bubbleH / 2)
        helloBubbleBG.fillColor = .init(white: 1, alpha: 0.9)
        helloBubbleBG.strokeColor = .clear

        helloBubble = SKNode()
        helloBubble.position = CGPoint(x: 0, y: size * 0.55 + 8)
        helloBubble.addChild(helloBubbleBG)
        helloBubble.addChild(helloText)
        helloBubble.alpha = 0
        helloBubble.setScale(0.8)

        super.init()

        addChild(bodySprite)
        addChild(statusLabel)
        addChild(projectLabel)
        addChild(helloBubble)
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    // MARK: - Status Updates

    func updateActivity(_ activity: SessionMonitor.Activity) {
        guard activity != currentActivity else { return }
        currentActivity = activity

        let newEmoji: String
        switch activity {
        case .reading:  newEmoji = "📖"
        case .talking:  newEmoji = "💬"
        case .waiting:  newEmoji = "❓"
        case .sleeping: newEmoji = "💤"
        }

        // Crossfade the status icon
        statusLabel.run(.sequence([
            .fadeOut(withDuration: 0.15),
            .run { [weak self] in self?.statusLabel.text = newEmoji },
            .fadeIn(withDuration: 0.15)
        ]))
    }

    // MARK: - Hello Interaction

    /// Call when gaze enters this character's hitbox.
    func gazeEntered() {
        guard !isHelloVisible else { return }
        dwellTimer?.invalidate()
        dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.showHello()
        }
    }

    /// Call when gaze leaves this character's hitbox.
    func gazeExited() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        hideHello()
    }

    private func showHello() {
        guard !isHelloVisible else { return }
        isHelloVisible = true
        helloBubble.removeAllActions()
        helloBubble.run(.group([
            .fadeIn(withDuration: 0.3),
            .scale(to: 1.0, duration: 0.3)
        ]))
    }

    private func hideHello() {
        guard isHelloVisible else { return }
        isHelloVisible = false
        helloBubble.removeAllActions()
        helloBubble.run(.group([
            .fadeOut(withDuration: 0.3),
            .scale(to: 0.8, duration: 0.3)
        ]))
    }

    // MARK: - Lifecycle Animations

    /// Fade in when a new session appears.
    func animateAppear() {
        alpha = 0
        setScale(0.5)
        run(.group([
            .fadeIn(withDuration: 0.5),
            .scale(to: 1.0, duration: 0.5)
        ]))
    }

    /// Show "Goodbye!" for 5 seconds, then fade out. Calls completion when done.
    func animateDisappear(completion: @escaping () -> Void) {
        // Show goodbye text in the hello bubble
        helloText.text = "Goodbye!"
        helloBubble.removeAllActions()
        helloBubble.alpha = 1
        helloBubble.setScale(1.0)

        run(.sequence([
            .wait(forDuration: 5.0),
            .fadeOut(withDuration: 1.0),
            .run(completion)
        ]))
    }

    /// Hitbox radius for gaze detection.
    var hitboxRadius: CGFloat { characterSize * 0.75 }

    /// Rescale the entire node to display at a new effective size.
    func rescale(to newSize: CGFloat) {
        let s = newSize / characterSize
        bodySprite.setScale(s)
        statusLabel.setScale(s)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Add the file to Xcode project and build.

Run: `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Glimpse/CharacterNode.swift Glimpse.xcodeproj/project.pbxproj
git commit -m "feat: add CharacterNode — sprite with status icon, label, and hello bubble"
```

---

### Task 4: PokemonScene — SKScene with Adaptive Grid & Gaze

**Files:**
- Create: `Glimpse/PokemonScene.swift`

Depends on: Tasks 1-3 (CharacterGenerator, SessionMonitor, CharacterNode).

- [ ] **Step 1: Create PokemonScene.swift**

```swift
// Glimpse/PokemonScene.swift
import SpriteKit

/// SpriteKit scene displaying Pokemon-styled characters for active Claude sessions.
final class PokemonScene: SKScene {

    private let sessionMonitor = SessionMonitor()
    private var characterNodes: [String: CharacterNode] = [:]  // sessionID → node
    private var departingNodes: Set<String> = []  // sessions currently fading out

    /// Empty-state label shown when no sessions are active.
    private let emptyLabel: SKLabelNode = {
        let label = SKLabelNode(fontNamed: "Menlo")
        label.text = "No Claude sessions active — start one to see your Pokemon!"
        label.fontSize = 16
        label.fontColor = .init(white: 0.4, alpha: 1)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.numberOfLines = 2
        label.preferredMaxLayoutWidth = 500
        return label
    }()

    /// Reference to the shared HeadTracker (set by SceneViewController).
    var headTracker: HeadTracker?

    // Gaze interaction state
    private var focusedCharacterID: String?
    private var lastUpdateTime: TimeInterval = 0

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .black
        addChild(emptyLabel)
        emptyLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)

        sessionMonitor.onUpdate = { [weak self] sessions in
            self?.handleSessionUpdate(sessions)
        }
        sessionMonitor.start()
    }

    override func willMove(from view: SKView) {
        sessionMonitor.stop()
    }

    // MARK: - Session Updates

    private func handleSessionUpdate(_ sessions: [SessionMonitor.Session]) {
        let activeIDs = Set(sessions.map(\.id))
        let existingIDs = Set(characterNodes.keys)

        // Remove departed sessions
        for id in existingIDs.subtracting(activeIDs) {
            guard !departingNodes.contains(id) else { continue }
            if let node = characterNodes[id] {
                departingNodes.insert(id)
                node.animateDisappear { [weak self] in
                    node.removeFromParent()
                    self?.characterNodes.removeValue(forKey: id)
                    self?.departingNodes.remove(id)
                    self?.relayout()
                }
            }
        }

        // Add new sessions
        let charSize = characterSize(for: sessions.count)
        for session in sessions {
            if let existing = characterNodes[session.id] {
                // Update activity
                existing.updateActivity(session.activity)
            } else {
                // New session — create character
                let node = CharacterNode(
                    sessionID: session.id,
                    projectName: session.projectName,
                    size: charSize
                )
                node.updateActivity(session.activity)
                node.animateAppear()
                addChild(node)
                characterNodes[session.id] = node
            }
        }

        // Update empty state
        emptyLabel.isHidden = !characterNodes.isEmpty

        relayout()
    }

    // MARK: - Adaptive Grid Layout

    private func characterSize(for count: Int) -> CGFloat {
        let cols = columns(for: count)
        let rows = CGFloat(ceil(Double(count) / Double(cols)))
        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / rows
        let s = min(cellW, cellH) * 0.55
        return min(max(s, 48), 96)
    }

    private func columns(for count: Int) -> Int {
        switch count {
        case 0, 1:  return 1
        case 2...4: return count
        case 5...9: return 3
        case 10...16: return 4
        default:    return 5
        }
    }

    private func relayout() {
        let activeNodes = characterNodes.values.filter { !departingNodes.contains($0.sessionID) }
        let count = activeNodes.count
        guard count > 0 else { return }

        let cols = columns(for: count)
        let rows = Int(ceil(Double(count) / Double(cols)))

        // Cell size — leave space for status icon and label
        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rows)

        // Grid offset to center the last (possibly incomplete) row
        let sorted = activeNodes.sorted { $0.sessionID < $1.sessionID }

        for (i, node) in sorted.enumerated() {
            let row = i / cols
            let col = i % cols

            // Items in this row (last row might have fewer)
            let itemsInRow = min(cols, count - row * cols)
            let rowOffsetX = (size.width - CGFloat(itemsInRow) * cellW) / 2

            let x = rowOffsetX + CGFloat(col) * cellW + cellW / 2
            // Top-to-bottom, with some vertical centering
            let totalGridH = CGFloat(rows) * cellH
            let gridOffsetY = (size.height - totalGridH) / 2
            let y = size.height - gridOffsetY - CGFloat(row) * cellH - cellH / 2

            let targetPos = CGPoint(x: x, y: y)

            // Animate position change
            node.removeAction(forKey: "reposition")
            node.run(.move(to: targetPos, duration: 0.3), withKey: "reposition")
        }

        // Resize characters if count changed
        let newSize = characterSize(for: count)
        for node in sorted {
            node.rescale(to: newSize)
        }
    }

    // MARK: - Head Tracking & Gaze

    override func update(_ currentTime: TimeInterval) {
        guard let tracker = headTracker else { return }

        let offset = tracker.latestOffset

        // Map head offset to screen position
        let gazeX = size.width  * 0.5 + CGFloat(offset.x) * size.width  * 0.5
        let gazeY = size.height * 0.5 + CGFloat(offset.y) * size.height * 0.5
        let gazePoint = CGPoint(x: gazeX, y: gazeY)

        // Find nearest character within hitbox
        var nearestID: String?
        var nearestDist: CGFloat = .greatestFiniteMagnitude

        for (id, node) in characterNodes {
            guard !departingNodes.contains(id) else { continue }
            let dist = hypot(node.position.x - gazePoint.x, node.position.y - gazePoint.y)
            if dist < node.hitboxRadius && dist < nearestDist {
                nearestDist = dist
                nearestID = id
            }
        }

        // Gaze enter / exit
        if nearestID != focusedCharacterID {
            // Exit previous
            if let prevID = focusedCharacterID, let prevNode = characterNodes[prevID] {
                prevNode.gazeExited()
            }
            // Enter new
            if let newID = nearestID, let newNode = characterNodes[newID] {
                newNode.gazeEntered()
            }
            focusedCharacterID = nearestID
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Add PokemonScene.swift to Xcode project and build.

Run: `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Glimpse/PokemonScene.swift Glimpse/CharacterNode.swift Glimpse.xcodeproj/project.pbxproj
git commit -m "feat: add PokemonScene — adaptive grid, gaze interaction, session lifecycle"
```

---

### Task 5: Wire Up — View Swapping & Theme Integration

**Files:**
- Modify: `Glimpse/SceneViewController.swift:50-68` (SceneEntry), `Glimpse/SceneViewController.swift:87-103` (discoverScenes), `Glimpse/SceneViewController.swift:197-223` (switchToScene)
- Modify: `Glimpse/DesktopWindowController.swift:6-58`
- Modify: `Glimpse/AppDelegate.swift` (minor — menu rebuild picks it up automatically)

This task connects all new components to the existing app.

- [ ] **Step 1: Add SpriteKit flag to SceneEntry and expose HeadTracker**

In `Glimpse/SceneViewController.swift`, modify the `SceneEntry` struct (lines 50-68) to add a `isSpriteKit` flag, and make `headTracker` accessible:

```swift
// SceneViewController.swift — replace the SceneEntry struct (lines 50-68):
struct SceneEntry {
    let id: String
    let displayName: String
    let cameraX: Float
    let cameraY: Float
    let cameraZ: Float
    let isSpriteKit: Bool
    fileprivate let builder: () -> SCNScene

    init(id: String, displayName: String, cameraX: Float = 0, cameraY: Float = 0, cameraZ: Float = 20, isSpriteKit: Bool = false, builder: @escaping () -> SCNScene = { SCNScene() }) {
        self.id = id
        self.displayName = displayName
        self.cameraX = cameraX
        self.cameraY = cameraY
        self.cameraZ = cameraZ
        self.isSpriteKit = isSpriteKit
        self.builder = builder
    }
}
```

Also change `headTracker` from `private` to `private(set)` on line 9:

```swift
// Line 9: change
private let headTracker = HeadTracker()
// to:
private(set) var headTracker = HeadTracker()
```

- [ ] **Step 2: Add Pokemon scene entry in discoverScenes()**

In `Glimpse/SceneViewController.swift`, add the Pokemon entry at the beginning of `discoverScenes()` (after line 87):

```swift
// At the top of discoverScenes(), before the model discovery:
availableScenes.append(SceneEntry(
    id: "pokemon_monitor",
    displayName: "Pokemon Monitor",
    isSpriteKit: true
))
```

- [ ] **Step 3: Update switchToScene() to handle SpriteKit themes**

In `Glimpse/SceneViewController.swift`, add a `pokemonScene` property and modify `switchToScene()`:

```swift
// Add property near line 85 (after currentScene):
private var pokemonScene: PokemonScene?

// Replace switchToScene() (lines 202-223) with:
func switchToScene(index: Int) {
    guard index < availableScenes.count else { return }
    currentSceneIndex = index
    UserDefaults.standard.set(availableScenes[index].id, forKey: "selectedSceneID")

    let entry = availableScenes[index]

    if entry.isSpriteKit {
        // Switching to SpriteKit theme — notify the window controller
        modelNode = nil
        currentScene = nil
        sceneView.scene = nil
        sceneView.isPlaying = false

        let pokemon = PokemonScene(size: view.bounds.size)
        pokemon.scaleMode = .resizeFill
        pokemon.headTracker = headTracker
        pokemonScene = pokemon

        // Tell the window controller to swap views
        NotificationCenter.default.post(
            name: .switchToSpriteKit,
            object: self,
            userInfo: ["scene": pokemon]
        )
    } else {
        // Switching to SceneKit theme
        pokemonScene = nil
        NotificationCenter.default.post(
            name: .switchToSceneKit,
            object: self
        )

        let scene = entry.builder()
        currentScene = scene
        currentCameraX = entry.cameraX
        currentCameraY = entry.cameraY
        currentCameraZ = entry.cameraZ
        cameraNode.position = SCNVector3(CGFloat(entry.cameraX), CGFloat(entry.cameraY), CGFloat(entry.cameraZ))
        scene.rootNode.addChildNode(cameraNode)
        sceneView.scene = scene
        updatePowerState()
    }
}
```

Add the notification names at the bottom of the file (after the extension):

```swift
extension Notification.Name {
    static let switchToSpriteKit = Notification.Name("Glimpse.switchToSpriteKit")
    static let switchToSceneKit  = Notification.Name("Glimpse.switchToSceneKit")
}
```

- [ ] **Step 4: Update DesktopWindowController to support view swapping**

Replace `Glimpse/DesktopWindowController.swift` with:

```swift
import AppKit
import SceneKit
import SpriteKit

/// An NSWindowController that pins a borderless, click-through window
/// just above the macOS desktop layer (below Finder icons).
final class DesktopWindowController: NSWindowController {

    private(set) var sceneViewController: SceneViewController?
    private var skView: SKView?

    convenience init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        win.collectionBehavior = [.stationary, .canJoinAllSpaces]
        win.isOpaque = true
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.backgroundColor = .black

        let vc = SceneViewController()
        win.contentViewController = vc
        win.setFrame(screen.frame, display: false)

        self.init(window: win)
        self.sceneViewController = vc

        setupViewSwapObservers()
    }

    override func showWindow(_ sender: Any?) {
        window?.orderFrontRegardless()
        setupOcclusionObserver()
    }

    // MARK: - View Swapping

    private func setupViewSwapObservers() {
        NotificationCenter.default.addObserver(
            forName: .switchToSpriteKit,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = notification.userInfo?["scene"] as? SKScene else { return }
            self?.swapToSpriteKit(scene: scene)
        }

        NotificationCenter.default.addObserver(
            forName: .switchToSceneKit,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.swapToSceneKit()
        }
    }

    private func swapToSpriteKit(scene: SKScene) {
        guard let window = window else { return }

        // Create SKView if needed
        if skView == nil {
            let sv = SKView(frame: window.contentView?.bounds ?? window.frame)
            sv.autoresizingMask = [.width, .height]
            sv.allowsTransparency = false
            sv.preferredFramesPerSecond = 60
            skView = sv
        }

        guard let sv = skView else { return }
        sv.presentScene(scene)

        // Swap: hide the SceneKit content, overlay SKView
        sceneViewController?.view.isHidden = true
        if sv.superview == nil {
            window.contentView?.addSubview(sv)
        }
        sv.isHidden = false
        sv.frame = window.contentView?.bounds ?? window.frame
    }

    private func swapToSceneKit() {
        skView?.presentScene(nil)
        skView?.isHidden = true
        sceneViewController?.view.isHidden = false
    }

    // MARK: - Occlusion

    private func setupOcclusionObserver() {
        guard let window = window else { return }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            let visible = window.occlusionState.contains(.visible)
            self?.sceneViewController?.setOccluded(!visible)
        }
    }
}
```

- [ ] **Step 5: Verify it compiles**

Run: `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Manual test — launch the app**

1. Build and run the app in Xcode
2. Check the menu bar — "Pokemon Monitor" should appear in the Theme submenu
3. Select it — screen should go dark with either characters (if Claude sessions active) or the empty-state message
4. Switch back to a 3D theme — should restore the previous SceneKit rendering
5. Ctrl+S should cycle through themes including Pokemon

- [ ] **Step 7: Commit**

```bash
git add Glimpse/SceneViewController.swift Glimpse/DesktopWindowController.swift Glimpse.xcodeproj/project.pbxproj
git commit -m "feat: wire up Pokemon theme — view swapping, menu entry, head tracking"
```

---

### Task 6: TODO.md — Deferred Work Tracker

**Files:**
- Create: `TODO.md`

- [ ] **Step 1: Create TODO.md with deferred items**

```markdown
# TODO

## Deferred

- [ ] **Cursor IDE session support** — Monitor Cursor sessions in addition to Claude Code. Requires discovering Cursor's log format and storage location.
- [ ] **Multi-monitor support** — Handle multiple screens for the Pokemon grid layout.
- [ ] **Character idle animations** — Subtle breathing / bobbing animation when a character is in sleeping state.
- [ ] **More character traits** — Expand the procedural generator with more body shapes, accessories (hats, scarves), and pattern variations.
```

- [ ] **Step 2: Commit**

```bash
git add TODO.md
git commit -m "docs: add TODO.md with deferred work items"
```

---

### Task 7: Integration Testing & Polish

**Files:**
- All new files (read-only verification)
- Potentially minor fixes to any file

This task is a full end-to-end manual test and polish pass.

- [ ] **Step 1: Build and launch the app**

Run: `xcodebuild -project Glimpse.xcodeproj -scheme Glimpse build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

Launch the app and switch to Pokemon Monitor theme.

- [ ] **Step 2: Test with active Claude sessions**

Open a new terminal and start a Claude Code session in any project. Within 5 seconds, a character should appear on the Pokemon theme with the project name below it.

Verify:
- Character fades in smoothly
- Status icon updates (try reading a file in the Claude session — should show 📖)
- Project name label is correct

- [ ] **Step 3: Test gaze interaction**

With head tracking active (camera or AirPods), look at a character. After ~300ms, "Hello!" bubble should fade in. Look away — bubble should fade out.

- [ ] **Step 4: Test session end**

Exit the Claude Code session. Within 5-10 seconds, the character should show "Goodbye!" for 5 seconds, then fade out.

- [ ] **Step 5: Test empty state**

With no Claude sessions active, the screen should show: "No Claude sessions active — start one to see your Pokemon!"

- [ ] **Step 6: Test theme switching**

Switch between Pokemon Monitor and a 3D theme (e.g., Basketball) multiple times. Verify:
- Clean transitions (no leftover sprites or 3D artifacts)
- Memory doesn't grow after multiple switches
- Head tracking works in both modes

- [ ] **Step 7: Fix any issues found and commit**

```bash
git add Glimpse/*.swift Glimpse.xcodeproj/project.pbxproj
git commit -m "fix: integration testing polish"
```
