// Glimpse/CharacterNode.swift
import SpriteKit

/// A single Pokemon-styled character representing a Claude Code session.
/// Contains: body sprite, status icon, project label, and hello bubble.
final class CharacterNode: SKNode {

    let sessionID: String
    let projectName: String

    private let bodySprite: SKSpriteNode
    private let cardBG: SKShapeNode
    private var glowNode: SKShapeNode?
    private let statusLabel: SKLabelNode
    private let activityWordLabel: SKLabelNode
    private let projectLabel: SKLabelNode
    private let topicLabel: SKLabelNode
    private let helloBubble: SKNode
    private var helloBubbleBG: SKShapeNode
    private let helloText: SKLabelNode

    /// Track current status to avoid redundant updates.
    private(set) var currentActivity: SessionMonitor.Activity = .sleeping

    /// Formatted idle duration text (e.g. "2min", "1h30m"), nil when not idle.
    private var idleDurationText: String?

    /// Whether the hello bubble is currently showing.
    private var isHelloVisible = false
    private var hasActivated = false
    private var isCountingDown = false

    /// Called when user gazes at this character long enough to trigger redirect.
    var onActivate: (() -> Void)?

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

        // Card background behind character
        let cardW = size * 1.6
        let cardH = size * 1.8
        cardBG = SKShapeNode(rectOf: CGSize(width: cardW, height: cardH), cornerRadius: 8)
        cardBG.fillColor = .init(red: 0.1, green: 0.1, blue: 0.15, alpha: 0.7)
        cardBG.strokeColor = .init(red: 0.3, green: 0.3, blue: 0.4, alpha: 0.4)
        cardBG.lineWidth = 1
        cardBG.zPosition = -2

        // Status icon label (emoji-based for simplicity)
        statusLabel = SKLabelNode(text: "💤")
        statusLabel.fontSize = size * 0.3
        statusLabel.position = CGPoint(x: size * 0.4, y: size * 0.35)
        statusLabel.verticalAlignmentMode = .center
        statusLabel.horizontalAlignmentMode = .center

        // Activity word label (above the emoji)
        activityWordLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        activityWordLabel.text = "idle"
        activityWordLabel.fontSize = max(size * 0.12, 8)
        activityWordLabel.fontColor = .init(white: 0.6, alpha: 1)
        activityWordLabel.position = CGPoint(x: size * 0.4, y: size * 0.35 + size * 0.2)
        activityWordLabel.verticalAlignmentMode = .center
        activityWordLabel.horizontalAlignmentMode = .center

        // Project name label
        projectLabel = SKLabelNode(fontNamed: "Menlo")
        projectLabel.text = projectName
        projectLabel.fontSize = max(size * 0.14, 9)
        projectLabel.fontColor = .init(white: 0.5, alpha: 1)
        projectLabel.position = CGPoint(x: 0, y: -size * 0.6 - 4)
        projectLabel.verticalAlignmentMode = .top
        projectLabel.horizontalAlignmentMode = .center

        // Topic label (below project label)
        topicLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        topicLabel.text = ""
        topicLabel.fontSize = max(size * 0.15, 10)
        topicLabel.fontColor = .init(white: 0.7, alpha: 1)
        let topicY: CGFloat = -size * 0.6 - 4 - projectLabel.fontSize - 2
        topicLabel.position = CGPoint(x: 0, y: topicY)
        topicLabel.verticalAlignmentMode = .top
        topicLabel.horizontalAlignmentMode = .center

        // Hello bubble (hidden by default)
        helloText = SKLabelNode(fontNamed: "Menlo")
        helloText.text = ""
        helloText.fontSize = 11
        helloText.fontColor = .init(red: 0.85, green: 0.95, blue: 0.85, alpha: 1) // bright green-white, terminal-like
        helloText.verticalAlignmentMode = .center
        helloText.horizontalAlignmentMode = .center
        helloText.numberOfLines = 0
        helloText.preferredMaxLayoutWidth = 300
        helloText.position = CGPoint(x: 0, y: 0)

        // Start with a reasonable default bubble size; updated dynamically in updateBubbleText
        helloBubbleBG = SKShapeNode(rectOf: CGSize(width: 100, height: 30), cornerRadius: 6)
        helloBubbleBG.fillColor = .init(white: 0.08, alpha: 0.92)
        helloBubbleBG.strokeColor = .init(red: 0.3, green: 0.5, blue: 0.3, alpha: 0.6)
        helloBubbleBG.lineWidth = 1

        helloBubble = SKNode()
        helloBubble.position = CGPoint(x: 0, y: size * 0.55 + 12)
        helloBubble.addChild(helloBubbleBG)
        helloBubble.addChild(helloText)
        helloBubble.alpha = 0
        helloBubble.setScale(0.8)

        super.init()

        addChild(cardBG)
        addChild(bodySprite)
        addChild(statusLabel)
        addChild(activityWordLabel)
        addChild(projectLabel)
        addChild(topicLabel)
        addChild(helloBubble)
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    // MARK: - Status Updates

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
            .run { [weak self] in
                self?.activityWordLabel.text = newWord
                if activity == .asking {
                    self?.activityWordLabel.fontColor = .init(red: 1.0, green: 0.55, blue: 0.0, alpha: 1)
                } else if previousActivity == .asking {
                    self?.activityWordLabel.fontColor = .init(white: 0.6, alpha: 1)
                }
            },
            .fadeIn(withDuration: 0.15)
        ]))

        // Asking state glow transitions
        if activity == .asking && previousActivity != .asking {
            showAskingGlow()
        } else if activity != .asking && previousActivity == .asking {
            hideAskingGlow()
        }
    }

    func updateTopic(_ topic: String) {
        guard topic != topicLabel.text else { return }
        topicLabel.text = topic
    }

    /// Update the idle duration and refresh the activity word label for standby states.
    func updateIdleDuration(_ seconds: TimeInterval) {
        let newText = Self.formatIdleDuration(seconds)
        guard newText != idleDurationText else { return }
        idleDurationText = newText
        // Update the word label live for standby states
        switch currentActivity {
        case .sleeping:
            activityWordLabel.text = newText ?? "idle"
        case .asking:
            activityWordLabel.text = newText.map { "ask \($0)" } ?? "ask"
        case .done:
            activityWordLabel.text = newText.map { "done \($0)" } ?? "done"
        default:
            break
        }
    }

    /// Format idle duration into a compact string: "30s", "2min", "1h30m".
    private static func formatIdleDuration(_ seconds: TimeInterval) -> String? {
        guard seconds >= 30 else { return nil }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h"
        }
        return "\(minutes)min"
    }

    /// Update the live log text shown in the bubble on gaze.
    private(set) var lastOutput: String = ""

    func updateLastOutput(_ output: String) {
        lastOutput = output
        // If bubble is currently visible, update it live
        if isHelloVisible {
            updateBubbleText(output)
        }
    }

    private func updateBubbleText(_ text: String) {
        let display = text.isEmpty ? "..." : text
        helloText.text = display

        // Resize bubble background to fit text
        let textFrame = helloText.frame
        let padding: CGFloat = 10
        let bgW = max(textFrame.width + padding * 2, 60)
        let bgH = max(textFrame.height + padding * 2, 24)

        helloBubbleBG.removeFromParent()
        let newBG = SKShapeNode(rectOf: CGSize(width: bgW, height: bgH), cornerRadius: 6)
        newBG.fillColor = .init(white: 0.08, alpha: 0.92)
        newBG.strokeColor = .init(red: 0.3, green: 0.5, blue: 0.3, alpha: 0.6)
        newBG.lineWidth = 1
        helloBubble.insertChild(newBG, at: 0)
        helloBubbleBG = newBG
    }

    // MARK: - Hello Interaction

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

    /// Call when gaze leaves this character's hitbox.
    func gazeExited() {
        removeAction(forKey: "dwell")
        removeAction(forKey: "activate")
        removeAction(forKey: "postActivate")
        cancelCountdown()
        hasActivated = false
        hideHello()
    }

    private func showHello() {
        guard !isHelloVisible else { return }
        isHelloVisible = true
        updateBubbleText(lastOutput)
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

    // MARK: - Countdown & Activation

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
        ]), withKey: "postActivate")
    }

    private func showCountdownText(_ value: Int) {
        let msg = "Redirecting to this agent in \(value)..."
        updateBubbleText(msg)
        // Change bubble style to warning (orange tint)
        helloBubbleBG.fillColor = .init(red: 0.15, green: 0.08, blue: 0.0, alpha: 0.92)
        helloBubbleBG.strokeColor = .init(red: 0.8, green: 0.5, blue: 0.1, alpha: 0.8)
        helloText.fontColor = .init(red: 1.0, green: 0.85, blue: 0.5, alpha: 1)
    }

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

    // MARK: - Lifecycle Animations

    /// Subtle idle breathing — body gently scales up and down.
    private func startBreathing() {
        let breathe = SKAction.sequence([
            .scaleY(to: 1.03, duration: 1.8),
            .scaleY(to: 0.97, duration: 1.8)
        ])
        bodySprite.run(.repeatForever(breathe), withKey: "breathing")

        // Slight vertical bob on the whole node
        let bob = SKAction.sequence([
            .moveBy(x: 0, y: 2, duration: 1.8),
            .moveBy(x: 0, y: -2, duration: 1.8)
        ])
        bodySprite.run(.repeatForever(bob), withKey: "bobbing")
    }

    private func stopBreathing() {
        bodySprite.removeAction(forKey: "breathing")
        bodySprite.removeAction(forKey: "bobbing")
    }

    /// Fade in when a new session appears.
    func animateAppear() {
        alpha = 0
        setScale(0.5)
        run(.sequence([
            .group([
                .fadeIn(withDuration: 0.5),
                .scale(to: 1.0, duration: 0.5)
            ]),
            .run { [weak self] in self?.startBreathing() }
        ]))
    }

    /// Show "Goodbye!" for 5 seconds, then fade out. Calls completion when done.
    func animateDisappear(completion: @escaping () -> Void) {
        stopBreathing()

        // Show goodbye text in the hello bubble
        helloText.text = "Goodbye!"
        updateBubbleText("Goodbye!")
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
    /// Skips helloBubble to avoid conflicting with its show/hide animations.
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
}
