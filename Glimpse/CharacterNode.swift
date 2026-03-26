// Glimpse/CharacterNode.swift
import SpriteKit

/// A character card representing a Claude Code session.
/// Contains: body sprite, status icon, project label, and topic labels.
final class CharacterNode: SKNode {

    let sessionID: String
    let projectName: String

    private let bodySprite: SKSpriteNode
    private let cardBG: SKShapeNode
    private var glowNode: SKNode?
    private let statusLabel: SKLabelNode
    private let activityWordLabel: SKLabelNode
    private let dividerNode: SKShapeNode
    private let folderPrefixLabel: SKLabelNode
    private let projectLabel: SKLabelNode
    private let topicLabel: SKLabelNode
    private let goodbyeLabel: SKLabelNode

    /// Track current status to avoid redundant updates.
    private(set) var currentActivity: SessionMonitor.Activity = .sleeping

    /// Formatted idle duration text (e.g. "2min", "1h30m"), nil when not idle.
    private var idleDurationText: String?

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

        // Status row: emoji + activity word centered below sprite
        let statusY = spriteY - size * 0.5 - size * 0.15
        statusLabel = SKLabelNode(text: "💤")
        statusLabel.fontSize = size * 0.25
        statusLabel.position = CGPoint(x: -size * 0.15, y: statusY)
        statusLabel.verticalAlignmentMode = .center
        statusLabel.horizontalAlignmentMode = .center

        activityWordLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        activityWordLabel.text = "idle"
        activityWordLabel.fontSize = max(size * 0.13, 9)
        activityWordLabel.fontColor = .init(red: 0.63, green: 0.63, blue: 0.69, alpha: 1)
        activityWordLabel.position = CGPoint(x: size * 0.15, y: statusY)
        activityWordLabel.verticalAlignmentMode = .center
        activityWordLabel.horizontalAlignmentMode = .left

        // Divider line between status row and project info
        let dividerY = statusY - size * 0.18
        let dividerPath = CGMutablePath()
        dividerPath.move(to: CGPoint(x: -cardW * 0.35, y: 0))
        dividerPath.addLine(to: CGPoint(x: cardW * 0.35, y: 0))
        dividerNode = SKShapeNode(path: dividerPath)
        dividerNode.strokeColor = .init(red: 0.3, green: 0.3, blue: 0.4, alpha: 0.3)
        dividerNode.lineWidth = 1
        dividerNode.position = CGPoint(x: 0, y: dividerY)

        // Project label: "folder:" prefix (dim) + project name (brighter)
        let projectFontSize = max(size * 0.10, 7)
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

        // Topic label (below project label, up to 3 lines)
        topicLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        topicLabel.text = ""
        topicLabel.fontSize = max(size * 0.11, 8)
        topicLabel.fontColor = .init(red: 0.7, green: 0.7, blue: 0.78, alpha: 1)
        topicLabel.numberOfLines = 3
        topicLabel.preferredMaxLayoutWidth = cardW - 20
        let topicY = projectY - projectFontSize - 4
        topicLabel.position = CGPoint(x: 0, y: topicY)
        topicLabel.verticalAlignmentMode = .top
        topicLabel.horizontalAlignmentMode = .center

        // Goodbye label (hidden, shown only during departure animation)
        goodbyeLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        goodbyeLabel.text = "Goodbye!"
        goodbyeLabel.fontSize = max(size * 0.16, 11)
        goodbyeLabel.fontColor = .init(red: 0.85, green: 0.95, blue: 0.85, alpha: 1)
        goodbyeLabel.position = CGPoint(x: 0, y: spriteY + size * 0.55 + 12)
        goodbyeLabel.verticalAlignmentMode = .center
        goodbyeLabel.horizontalAlignmentMode = .center
        goodbyeLabel.alpha = 0

        super.init()

        addChild(cardBG)
        addChild(bodySprite)
        addChild(statusLabel)
        addChild(activityWordLabel)
        addChild(dividerNode)
        addChild(folderPrefixLabel)
        addChild(projectLabel)
        addChild(topicLabel)
        addChild(goodbyeLabel)
    }

    /// Bounds of the card background in local coordinates, for hit-testing.
    var cardBounds: CGRect {
        cardBG.frame
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
                    self?.activityWordLabel.fontColor = .init(red: 0.63, green: 0.63, blue: 0.69, alpha: 1)
                }
            },
            .fadeIn(withDuration: 0.15)
        ]))

        if activity == .asking && previousActivity != .asking {
            showAskingGlow()
        } else if activity != .asking && previousActivity == .asking {
            hideAskingGlow()
        }
    }

    func updateTopics(_ topics: [String]) {
        let joined = topics.isEmpty ? "nothing" : topics.joined(separator: "\n")
        guard joined != topicLabel.text else { return }
        topicLabel.text = joined
    }

    /// Update the idle duration and refresh the activity word label for standby states.
    func updateIdleDuration(_ seconds: TimeInterval) {
        let newText = Self.formatIdleDuration(seconds)
        guard newText != idleDurationText else { return }
        idleDurationText = newText
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

    // MARK: - Asking State Glow

    private func showAskingGlow() {
        guard glowNode == nil else { return }

        let container = SKNode()
        container.zPosition = -1.5  // between card bg (-2) and body
        container.alpha = 0

        // Card dimensions matching cardBG
        let cardW = characterSize * 2.0
        let cardH = characterSize * 2.6
        let cornerR: CGFloat = 8
        let layerCount = 14
        let maxSpread: CGFloat = 18

        // Concentric rounded-rect layers with decreasing opacity
        for i in (1...layerCount).reversed() {
            let spread = maxSpread * CGFloat(i) / CGFloat(layerCount)
            let layerW = cardW + spread * 2
            let layerH = cardH + spread * 2
            let layerR = cornerR + spread * 0.5

            let layer = SKShapeNode(rectOf: CGSize(width: layerW, height: layerH), cornerRadius: layerR)
            layer.fillColor = .clear
            // Quadratic falloff: brighter near card, fading outward
            let t = 1.0 - CGFloat(i) / CGFloat(layerCount)
            let layerAlpha = 0.6 * t * t
            layer.strokeColor = .init(red: 1.0, green: 0.55, blue: 0.0, alpha: layerAlpha)
            layer.lineWidth = 2
            layer.glowWidth = 0
            container.addChild(layer)
        }

        // Orange border on card itself
        let border = SKShapeNode(rectOf: CGSize(width: cardW, height: cardH), cornerRadius: cornerR)
        border.fillColor = .clear
        border.strokeColor = .init(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.5)
        border.lineWidth = 1.5
        container.addChild(border)

        addChild(container)
        glowNode = container

        // Pulse animation: fade between 0.3 and 1.0 alpha
        let fadeUp = SKAction.fadeAlpha(to: 1.0, duration: 0.8)
        fadeUp.timingMode = .easeInEaseOut
        let fadeDown = SKAction.fadeAlpha(to: 0.5, duration: 0.8)
        fadeDown.timingMode = .easeInEaseOut
        let pulse = SKAction.repeatForever(.sequence([fadeUp, fadeDown]))

        container.run(.sequence([
            .fadeIn(withDuration: 0.3),
            pulse
        ]), withKey: "askingGlow")

        cardBG.strokeColor = .init(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.5)
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
        cardBG.strokeColor = .init(red: 0.3, green: 0.3, blue: 0.4, alpha: 0.4)
    }

    // MARK: - Lifecycle Animations

    private func startBreathing() {
        let breathe = SKAction.sequence([
            .scaleY(to: 1.03, duration: 1.8),
            .scaleY(to: 0.97, duration: 1.8)
        ])
        bodySprite.run(.repeatForever(breathe), withKey: "breathing")

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
        goodbyeLabel.run(.fadeIn(withDuration: 0.3))

        run(.sequence([
            .wait(forDuration: 5.0),
            .fadeOut(withDuration: 1.0),
            .run(completion)
        ]))
    }

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
        goodbyeLabel.setScale(s)
        glowNode?.setScale(s)
    }
}
