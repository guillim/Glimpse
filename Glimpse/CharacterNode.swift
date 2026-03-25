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
    private let topicLabel: SKLabelNode
    private let helloBubble: SKNode
    private var helloBubbleBG: SKShapeNode
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

        addChild(bodySprite)
        addChild(statusLabel)
        addChild(projectLabel)
        addChild(topicLabel)
        addChild(helloBubble)
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    deinit {
        dwellTimer?.invalidate()
    }

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

    func updateTopic(_ topic: String) {
        guard topic != topicLabel.text else { return }
        topicLabel.text = topic
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
    /// Skips helloBubble to avoid conflicting with its show/hide animations.
    func rescale(to newSize: CGFloat) {
        let s = newSize / characterSize
        bodySprite.setScale(s)
        statusLabel.setScale(s)
        projectLabel.setScale(s)
        topicLabel.setScale(s)
    }
}
