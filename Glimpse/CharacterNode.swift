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
    /// Skips helloBubble to avoid conflicting with its show/hide animations.
    func rescale(to newSize: CGFloat) {
        let s = newSize / characterSize
        bodySprite.setScale(s)
        statusLabel.setScale(s)
        projectLabel.setScale(s)
    }
}
