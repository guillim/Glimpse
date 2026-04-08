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
    /// Office-style 3D effect nodes (nil when using kawaii style).
    private var shadowNode: SKSpriteNode?
    private var highlightNode: SKSpriteNode?
    private let pillBG: SKShapeNode
    private let statusDot: SKShapeNode
    private let activityWordLabel: SKLabelNode
    private let durationLabel: SKLabelNode
    private let dividerNode: SKShapeNode
    private let folderPrefixLabel: SKLabelNode
    private let projectLabel: SKLabelNode
    private let workingOnPrefix: SKLabelNode
    private let topicLabel: SKLabelNode
    private let statusPrefix: SKLabelNode
    private let statusDetailLabel: SKLabelNode
    private let goodbyeLabel: SKLabelNode

    /// Track current status to avoid redundant updates.
    private(set) var currentActivity: SessionMonitor.Activity = .sleeping

    /// Current question text when in .asking state.
    private var currentAssistantText: String?

    /// Formatted idle duration text (e.g. "2min", "1h30m"), nil when not idle.
    private var idleDurationText: String?

    /// The character size (width & height of the body sprite).
    let characterSize: CGFloat

    init(sessionID: String, projectName: String, size: CGFloat) {
        self.sessionID = sessionID
        self.projectName = projectName
        self.characterSize = size

        // Body sprite from active character style
        let texture = Self.makeTexture(sessionID: sessionID, size: size)
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
        let spriteY = cardH * 0.22
        bodySprite.position = CGPoint(x: 0, y: spriteY)

        // Office-style 3D effect: shadow beneath character + highlight overlay
        if CharacterStyle.current != .kawaii {
            shadowNode = Self.makeShadowNode(size: size, spriteY: spriteY)
            highlightNode = Self.makeHighlightNode(size: size, spriteY: spriteY)
        }

        // Top row Y: near top edge of card
        let topRowY = cardH * 0.5 - size * 0.12
        let padding = size * 0.12

        // ── Top-left: activity dot + verb + duration ──
        pillBG = SKShapeNode(rectOf: CGSize(width: 1, height: 1), cornerRadius: 0)
        pillBG.fillColor = .clear
        pillBG.strokeColor = .clear
        pillBG.isHidden = true  // No pill background in new layout

        let dotR = max(size * 0.03, 2.5)
        statusDot = SKShapeNode(circleOfRadius: dotR)
        statusDot.fillColor = .init(red: 0.4, green: 0.4, blue: 0.47, alpha: 1)
        statusDot.strokeColor = .clear
        statusDot.glowWidth = max(size * 0.02, 1.5)
        statusDot.position = CGPoint(x: -cardW * 0.5 + padding, y: topRowY)

        activityWordLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        activityWordLabel.text = "IDLE"
        activityWordLabel.fontSize = max(size * 0.09, 7)
        activityWordLabel.fontColor = .init(red: 0.53, green: 0.53, blue: 0.58, alpha: 1)
        activityWordLabel.position = CGPoint(x: -cardW * 0.5 + padding + dotR * 2 + 4, y: topRowY)
        activityWordLabel.verticalAlignmentMode = .center
        activityWordLabel.horizontalAlignmentMode = .left

        durationLabel = SKLabelNode(fontNamed: "Menlo")
        durationLabel.text = ""
        durationLabel.fontSize = max(size * 0.08, 6)
        durationLabel.fontColor = .init(red: 0.45, green: 0.45, blue: 0.52, alpha: 1)
        // Position dynamically after verb — set initial position, updated in updateActivity
        durationLabel.position = CGPoint(x: 0, y: topRowY)
        durationLabel.verticalAlignmentMode = .center
        durationLabel.horizontalAlignmentMode = .left

        // ── Top-right: 📁 + project name ──
        let projectFontSize = max(size * 0.08, 6)

        folderPrefixLabel = SKLabelNode(fontNamed: "Menlo")
        folderPrefixLabel.text = "📁"
        folderPrefixLabel.fontSize = projectFontSize
        folderPrefixLabel.fontColor = .init(red: 0.45, green: 0.45, blue: 0.52, alpha: 1)
        folderPrefixLabel.verticalAlignmentMode = .center
        folderPrefixLabel.horizontalAlignmentMode = .right

        projectLabel = SKLabelNode(fontNamed: "Menlo")
        // Initial truncation — will be refined by repositionFolder()
        projectLabel.text = Self.truncateProjectName(projectName, maxChars: 8)
        projectLabel.fontSize = projectFontSize
        projectLabel.fontColor = .init(red: 0.5, green: 0.5, blue: 0.56, alpha: 1)
        projectLabel.verticalAlignmentMode = .center
        projectLabel.horizontalAlignmentMode = .right

        // Position right-aligned — refined dynamically by repositionFolder()
        projectLabel.position = CGPoint(x: cardW * 0.5 - padding, y: topRowY)
        folderPrefixLabel.position = CGPoint(x: cardW * 0.5 - padding - projectLabel.frame.width - 2, y: topRowY)

        // Divider — hidden in new layout
        let dividerPath = CGMutablePath()
        dividerPath.move(to: CGPoint(x: -cardW * 0.35, y: 0))
        dividerPath.addLine(to: CGPoint(x: cardW * 0.35, y: 0))
        dividerNode = SKShapeNode(path: dividerPath)
        dividerNode.strokeColor = .clear
        dividerNode.lineWidth = 0
        dividerNode.isHidden = true

        // ── Below character: topic + status detail (more room now) ──
        let contentFontSize = max(size * 0.09, 7)
        let sectionPadding: CGFloat = 8
        let sectionLeftX = -cardW * 0.5 + sectionPadding
        let sectionMaxWidth = cardW - sectionPadding * 2

        // Topic — positioned right below the character sprite
        let topicY = spriteY - size * 0.5 - size * 0.1
        workingOnPrefix = SKLabelNode(fontNamed: "Menlo")
        workingOnPrefix.text = ""
        workingOnPrefix.fontSize = contentFontSize
        workingOnPrefix.fontColor = .clear
        workingOnPrefix.isHidden = true

        topicLabel = SKLabelNode(fontNamed: "Menlo")
        topicLabel.text = ""
        topicLabel.fontSize = contentFontSize
        topicLabel.fontColor = .init(red: 0.78, green: 0.72, blue: 0.45, alpha: 1)
        topicLabel.numberOfLines = 1
        topicLabel.preferredMaxLayoutWidth = sectionMaxWidth
        topicLabel.position = CGPoint(x: sectionLeftX, y: topicY)
        topicLabel.verticalAlignmentMode = .top
        topicLabel.horizontalAlignmentMode = .left

        // Status detail — right below topic, more lines available now
        let statusSectionY = topicY - contentFontSize - 3
        statusPrefix = SKLabelNode(fontNamed: "Menlo")
        statusPrefix.text = ""
        statusPrefix.fontSize = contentFontSize
        statusPrefix.fontColor = .clear
        statusPrefix.isHidden = true

        statusDetailLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        statusDetailLabel.text = ""
        statusDetailLabel.fontSize = contentFontSize
        statusDetailLabel.fontColor = .init(red: 0.5, green: 0.5, blue: 0.56, alpha: 1)
        statusDetailLabel.numberOfLines = 6
        statusDetailLabel.preferredMaxLayoutWidth = sectionMaxWidth
        statusDetailLabel.position = CGPoint(x: sectionLeftX, y: statusSectionY)
        statusDetailLabel.verticalAlignmentMode = .top
        statusDetailLabel.horizontalAlignmentMode = .left

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
        if let shadow = shadowNode { addChild(shadow) }
        addChild(bodySprite)
        if let highlight = highlightNode { addChild(highlight) }
        addChild(pillBG)
        addChild(statusDot)
        addChild(activityWordLabel)
        addChild(durationLabel)
        addChild(dividerNode)
        addChild(folderPrefixLabel)
        addChild(projectLabel)
        addChild(workingOnPrefix)
        addChild(topicLabel)
        addChild(statusPrefix)
        addChild(statusDetailLabel)
        addChild(goodbyeLabel)

        // Initial folder positioning based on default "IDLE" verb width
        repositionFolder()
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    // MARK: - Status Updates

    /// Activity color palette: (dot fill, dot glow, text color, pill fill, pill stroke).
    private static func activityColors(_ activity: SessionMonitor.Activity)
        -> (dot: NSColor, glow: NSColor, text: NSColor, pillFill: NSColor, pillStroke: NSColor)
    {
        switch activity {
        case .reading:
            return (NSColor(red: 0.35, green: 0.63, blue: 1.0, alpha: 1),
                    NSColor(red: 0.35, green: 0.63, blue: 1.0, alpha: 0.6),
                    NSColor(red: 0.54, green: 0.77, blue: 1.0, alpha: 1),
                    NSColor(red: 0.35, green: 0.63, blue: 1.0, alpha: 0.15),
                    NSColor(red: 0.35, green: 0.63, blue: 1.0, alpha: 0.3))
        case .writing:
            return (NSColor(red: 0.31, green: 0.78, blue: 0.47, alpha: 1),
                    NSColor(red: 0.31, green: 0.78, blue: 0.47, alpha: 0.6),
                    NSColor(red: 0.47, green: 0.91, blue: 0.63, alpha: 1),
                    NSColor(red: 0.31, green: 0.78, blue: 0.47, alpha: 0.15),
                    NSColor(red: 0.31, green: 0.78, blue: 0.47, alpha: 0.3))
        case .running:
            return (NSColor(red: 1.0, green: 0.78, blue: 0.24, alpha: 1),
                    NSColor(red: 1.0, green: 0.78, blue: 0.24, alpha: 0.6),
                    NSColor(red: 1.0, green: 0.88, blue: 0.50, alpha: 1),
                    NSColor(red: 1.0, green: 0.78, blue: 0.24, alpha: 0.15),
                    NSColor(red: 1.0, green: 0.78, blue: 0.24, alpha: 0.3))
        case .testing:
            return (NSColor(red: 0.25, green: 0.80, blue: 0.75, alpha: 1),
                    NSColor(red: 0.25, green: 0.80, blue: 0.75, alpha: 0.6),
                    NSColor(red: 0.45, green: 0.92, blue: 0.88, alpha: 1),
                    NSColor(red: 0.25, green: 0.80, blue: 0.75, alpha: 0.15),
                    NSColor(red: 0.25, green: 0.80, blue: 0.75, alpha: 0.3))
        case .building:
            return (NSColor(red: 0.92, green: 0.65, blue: 0.20, alpha: 1),
                    NSColor(red: 0.92, green: 0.65, blue: 0.20, alpha: 0.6),
                    NSColor(red: 1.0, green: 0.80, blue: 0.45, alpha: 1),
                    NSColor(red: 0.92, green: 0.65, blue: 0.20, alpha: 0.15),
                    NSColor(red: 0.92, green: 0.65, blue: 0.20, alpha: 0.3))
        case .committing:
            return (NSColor(red: 0.85, green: 0.40, blue: 0.75, alpha: 1),
                    NSColor(red: 0.85, green: 0.40, blue: 0.75, alpha: 0.6),
                    NSColor(red: 0.95, green: 0.58, blue: 0.88, alpha: 1),
                    NSColor(red: 0.85, green: 0.40, blue: 0.75, alpha: 0.15),
                    NSColor(red: 0.85, green: 0.40, blue: 0.75, alpha: 0.3))
        case .thinking:
            return (NSColor(red: 0.66, green: 0.51, blue: 1.0, alpha: 1),
                    NSColor(red: 0.66, green: 0.51, blue: 1.0, alpha: 0.6),
                    NSColor(red: 0.77, green: 0.66, blue: 1.0, alpha: 1),
                    NSColor(red: 0.66, green: 0.51, blue: 1.0, alpha: 0.15),
                    NSColor(red: 0.66, green: 0.51, blue: 1.0, alpha: 0.3))
        case .processing:
            return (NSColor(red: 0.55, green: 0.45, blue: 0.82, alpha: 1),
                    NSColor(red: 0.55, green: 0.45, blue: 0.82, alpha: 0.5),
                    NSColor(red: 0.70, green: 0.60, blue: 0.92, alpha: 1),
                    NSColor(red: 0.55, green: 0.45, blue: 0.82, alpha: 0.12),
                    NSColor(red: 0.55, green: 0.45, blue: 0.82, alpha: 0.25))
        case .spawning:
            return (NSColor(red: 1.0, green: 0.71, blue: 0.39, alpha: 1),
                    NSColor(red: 1.0, green: 0.71, blue: 0.39, alpha: 0.6),
                    NSColor(red: 1.0, green: 0.82, blue: 0.63, alpha: 1),
                    NSColor(red: 1.0, green: 0.71, blue: 0.39, alpha: 0.15),
                    NSColor(red: 1.0, green: 0.71, blue: 0.39, alpha: 0.3))
        case .searching:
            return (NSColor(red: 0.39, green: 0.82, blue: 0.86, alpha: 1),
                    NSColor(red: 0.39, green: 0.82, blue: 0.86, alpha: 0.6),
                    NSColor(red: 0.56, green: 0.91, blue: 0.94, alpha: 1),
                    NSColor(red: 0.39, green: 0.82, blue: 0.86, alpha: 0.15),
                    NSColor(red: 0.39, green: 0.82, blue: 0.86, alpha: 0.3))
        case .asking:
            return (NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1),
                    NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.6),
                    NSColor(red: 1.0, green: 0.69, blue: 0.38, alpha: 1),
                    NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.15),
                    NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.3))
        case .done:
            return (NSColor(red: 0.39, green: 0.78, blue: 0.39, alpha: 1),
                    NSColor(red: 0.39, green: 0.78, blue: 0.39, alpha: 0.6),
                    NSColor(red: 0.56, green: 0.91, blue: 0.56, alpha: 1),
                    NSColor(red: 0.39, green: 0.78, blue: 0.39, alpha: 0.15),
                    NSColor(red: 0.39, green: 0.78, blue: 0.39, alpha: 0.3))
        case .sleeping:
            return (NSColor(red: 0.4, green: 0.4, blue: 0.47, alpha: 1),
                    NSColor(red: 0.4, green: 0.4, blue: 0.47, alpha: 0.3),
                    NSColor(red: 0.53, green: 0.53, blue: 0.58, alpha: 1),
                    NSColor(red: 0.39, green: 0.39, blue: 0.47, alpha: 0.12),
                    NSColor(red: 0.39, green: 0.39, blue: 0.47, alpha: 0.2))
        }
    }

    func updateActivity(_ activity: SessionMonitor.Activity, lastAssistantText: String? = nil) {
        guard activity != currentActivity || lastAssistantText != currentAssistantText else { return }
        let previousActivity = currentActivity
        currentActivity = activity
        currentAssistantText = lastAssistantText

        let newWord: String
        switch activity {
        case .reading:    newWord = "READ"
        case .writing:    newWord = "WRITE"
        case .running:    newWord = "RUN"
        case .testing:    newWord = "TEST"
        case .building:   newWord = "BUILD"
        case .committing: newWord = "COMMIT"
        case .thinking:   newWord = "THINK"
        case .processing: newWord = "PROCESS"
        case .spawning:   newWord = "SPAWN"
        case .searching:  newWord = "SEARCH"
        case .asking:     newWord = "ASK"
        case .done:       newWord = "DONE"
        case .sleeping:   newWord = "IDLE"
        }

        // Update status detail — always show last sentence of assistant's message
        let statusText: String
        let statusColor: NSColor
        if let text = lastAssistantText, !text.isEmpty {
            let lastSentence = Self.extractLastSentence(from: text)
            statusText = lastSentence.count > 180 ? String(lastSentence.prefix(179)) + "…" : lastSentence
        } else {
            statusText = ""
        }
        if activity == .asking {
            statusColor = NSColor(red: 1.0, green: 0.69, blue: 0.38, alpha: 1)
        } else {
            statusColor = NSColor(red: 0.5, green: 0.5, blue: 0.56, alpha: 1)
        }
        let styledText = statusText.isEmpty
            ? NSAttributedString()
            : Self.markdownAttributedString(from: statusText, fontSize: statusDetailLabel.fontSize, baseColor: statusColor)
        statusDetailLabel.run(.sequence([
            .fadeOut(withDuration: 0.12),
            .run { [weak self] in
                self?.statusDetailLabel.attributedText = styledText
            },
            .fadeIn(withDuration: 0.12)
        ]))

        // Show duration next to verb for standby states
        durationLabel.text = Self.showsDuration(activity) ? (idleDurationText ?? "") : ""
        // Position duration label right after the verb text
        durationLabel.position.x = activityWordLabel.position.x + activityWordLabel.frame.width + 4
        // Reposition folder to avoid overlap with new verb/duration width
        repositionFolder()

        let colors = Self.activityColors(activity)

        // Animate pill color transition
        let pillContainer = pillBG
        let dot = statusDot
        pillContainer.run(.sequence([
            .fadeOut(withDuration: 0.12),
            .run {
                pillContainer.fillColor = colors.pillFill
                pillContainer.strokeColor = colors.pillStroke
            },
            .fadeIn(withDuration: 0.12)
        ]))

        dot.run(.sequence([
            .fadeOut(withDuration: 0.12),
            .run {
                dot.fillColor = colors.dot
                dot.glowWidth = 3
            },
            .fadeIn(withDuration: 0.12)
        ]))

        activityWordLabel.run(.sequence([
            .fadeOut(withDuration: 0.12),
            .run { [weak self] in
                self?.activityWordLabel.text = newWord
                self?.activityWordLabel.fontColor = colors.text
            },
            .fadeIn(withDuration: 0.12)
        ]))

        // Pulsing dot for asking state
        if activity == .asking {
            let pulseUp = SKAction.scale(to: 1.4, duration: 0.6)
            pulseUp.timingMode = .easeInEaseOut
            let pulseDown = SKAction.scale(to: 0.7, duration: 0.6)
            pulseDown.timingMode = .easeInEaseOut
            dot.run(.repeatForever(.sequence([pulseUp, pulseDown])), withKey: "dotPulse")
        } else if previousActivity == .asking {
            dot.removeAction(forKey: "dotPulse")
            dot.run(.scale(to: 1.0, duration: 0.2))
        }

        if activity == .asking && previousActivity != .asking {
            showAskingGlow()
        } else if activity != .asking && previousActivity == .asking {
            hideAskingGlow()
        }
    }

    func updateSummary(_ summary: String) {
        let maxChars = Int(topicLabel.preferredMaxLayoutWidth / (topicLabel.fontSize * 0.65))
        let display: String
        if summary.count > maxChars {
            let prefix = String(summary.prefix(maxChars))
            if let lastSpace = prefix.lastIndex(of: " ") {
                display = String(prefix[..<lastSpace]) + "..."
            } else {
                display = String(summary.prefix(maxChars - 1)) + "..."
            }
        } else {
            display = summary
        }
        guard display != topicLabel.text else { return }
        topicLabel.text = display
    }

    /// Whether this activity shows duration outside the pill.
    private static func showsDuration(_ activity: SessionMonitor.Activity) -> Bool {
        switch activity {
        case .sleeping, .asking, .done: return true
        default: return false
        }
    }

    /// Truncate project name to fit within maxChars.
    static func truncateProjectName(_ name: String, maxChars: Int) -> String {
        guard name.count > maxChars else { return name }
        return String(name.prefix(maxChars - 1)) + "…"
    }

    /// Dynamically reposition the folder label to avoid overlapping the activity labels.
    /// Computes available right-side space and truncates the project name as needed.
    private func repositionFolder() {
        let cardW = characterSize * 2.0
        let padding = characterSize * 0.12
        let gap = characterSize * 0.15  // minimum gap between left and right sections

        // Measure left side: dot + verb + duration
        let leftEdge: CGFloat
        if durationLabel.text?.isEmpty == false {
            leftEdge = durationLabel.position.x + durationLabel.frame.width
        } else {
            leftEdge = activityWordLabel.position.x + activityWordLabel.frame.width
        }

        // Available width for emoji + project name on the right
        let rightEdge = cardW * 0.5 - padding
        let emojiWidth = characterSize * 0.14  // approximate 📁 width
        let availableForName = rightEdge - leftEdge - gap - emojiWidth - 4

        // Estimate chars that fit (monospace: ~0.6 * fontSize per char)
        let charWidth = projectLabel.fontSize * 0.6
        let maxChars = max(Int(availableForName / charWidth), 3)

        projectLabel.text = Self.truncateProjectName(projectName, maxChars: maxChars)
        projectLabel.position = CGPoint(x: rightEdge, y: projectLabel.position.y)
        folderPrefixLabel.position = CGPoint(x: rightEdge - projectLabel.frame.width - 2, y: folderPrefixLabel.position.y)
    }

    /// Extract the last sentence from a text block.
    /// Splits on sentence-ending punctuation and newlines, returns the last non-empty segment.
    private static func extractLastSentence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Split on sentence boundaries: periods, exclamation marks, question marks, and newlines
        let segments = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // Return last segment; if the original ended with "?" re-append it
        guard let last = segments.last else { return trimmed }
        if trimmed.hasSuffix("?") { return last + "?" }
        if trimmed.hasSuffix("!") { return last + "!" }
        return last
    }

    /// Parse simple markdown patterns into an NSAttributedString.
    /// Supports: `code`, **bold**, *italic* / _italic_
    private static func markdownAttributedString(
        from text: String,
        fontSize: CGFloat,
        baseColor: NSColor
    ) -> NSAttributedString {
        let baseFont = NSFont(name: "Menlo", size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let boldFont = NSFont(name: "Menlo-Bold", size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let italicFont = NSFont(name: "Menlo-Italic", size: fontSize) ?? NSFont(name: "Menlo-Oblique", size: fontSize) ?? baseFont

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: baseColor
        ]
        let codeColor = NSColor(red: 0.45, green: 0.82, blue: 0.82, alpha: 1)  // teal
        let boldColor = NSColor(red: 0.78, green: 0.78, blue: 0.84, alpha: 1)  // brighter white
        let italicColor = NSColor(red: 0.58, green: 0.58, blue: 0.68, alpha: 1)  // slightly muted

        // Patterns: `code`, **bold**, *italic* (greedy-safe, non-nested)
        let patterns: [(regex: NSRegularExpression, attrs: [NSAttributedString.Key: Any], group: Int)] = [
            (try! NSRegularExpression(pattern: "`([^`]+)`"), [.font: baseFont, .foregroundColor: codeColor], 1),
            (try! NSRegularExpression(pattern: "\\*\\*([^*]+)\\*\\*"), [.font: boldFont, .foregroundColor: boldColor], 1),
            (try! NSRegularExpression(pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)"), [.font: italicFont, .foregroundColor: italicColor], 1),
            (try! NSRegularExpression(pattern: "(?<!_)_([^_]+)_(?!_)"), [.font: italicFont, .foregroundColor: italicColor], 1),
        ]

        // Collect all matches with their ranges and replacement info
        struct MatchInfo {
            let fullRange: NSRange
            let contentRange: NSRange
            let attrs: [NSAttributedString.Key: Any]
        }

        let nsText = text as NSString
        var matches: [MatchInfo] = []
        for p in patterns {
            let results = p.regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for r in results {
                matches.append(MatchInfo(fullRange: r.range, contentRange: r.range(at: p.group), attrs: p.attrs))
            }
        }

        // Sort by position, remove overlaps (first match wins)
        matches.sort { $0.fullRange.location < $1.fullRange.location }
        var filtered: [MatchInfo] = []
        var lastEnd = 0
        for m in matches {
            if m.fullRange.location >= lastEnd {
                filtered.append(m)
                lastEnd = m.fullRange.location + m.fullRange.length
            }
        }

        // Build attributed string: plain text between matches, styled content for matches
        let result = NSMutableAttributedString()
        var cursor = 0
        for m in filtered {
            // Append plain text before this match
            if m.fullRange.location > cursor {
                let plainRange = NSRange(location: cursor, length: m.fullRange.location - cursor)
                let plain = nsText.substring(with: plainRange)
                result.append(NSAttributedString(string: plain, attributes: baseAttrs))
            }
            // Append styled content (without the markdown delimiters)
            let content = nsText.substring(with: m.contentRange)
            result.append(NSAttributedString(string: content, attributes: m.attrs.merging(baseAttrs) { new, _ in new }))
            cursor = m.fullRange.location + m.fullRange.length
        }
        // Append remaining plain text
        if cursor < nsText.length {
            let remaining = nsText.substring(from: cursor)
            result.append(NSAttributedString(string: remaining, attributes: baseAttrs))
        }

        return result
    }


    /// Update the idle duration and refresh the duration label for standby states.
    func updateIdleDuration(_ seconds: TimeInterval) {
        let newText = Self.formatIdleDuration(seconds)
        guard newText != idleDurationText else { return }
        idleDurationText = newText
        if Self.showsDuration(currentActivity) {
            durationLabel.text = newText ?? ""
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
        if CharacterStyle.current != .kawaii {
            startOfficeAnimations()
        } else {
            startKawaiiBreathing()
        }
    }

    private func stopBreathing() {
        bodySprite.removeAction(forKey: "breathing")
        bodySprite.removeAction(forKey: "bobbing")
        bodySprite.removeAction(forKey: "sway")
        shadowNode?.removeAction(forKey: "shadowSway")
        highlightNode?.removeAction(forKey: "highlightDrift")
    }

    private func startKawaiiBreathing() {
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

    // MARK: - Office 3D Animations

    private func startOfficeAnimations() {
        // 1. Gentle sway — subtle rotation ±1.5 degrees + slight X drift
        let swayDuration: TimeInterval = 3.5
        let swayAngle = CGFloat.pi / 120  // ~1.5 degrees
        let sway = SKAction.sequence([
            .group([
                .rotate(toAngle: swayAngle, duration: swayDuration, shortestUnitArc: true),
                .moveBy(x: 1.5, y: 0, duration: swayDuration)
            ]),
            .group([
                .rotate(toAngle: -swayAngle, duration: swayDuration, shortestUnitArc: true),
                .moveBy(x: -1.5, y: 0, duration: swayDuration)
            ]),
        ])
        bodySprite.run(.repeatForever(sway), withKey: "sway")

        // 2. Breathing — subtle Y-scale pulse
        let breathe = SKAction.sequence([
            .scaleY(to: 1.015, duration: 2.2),
            .scaleY(to: 0.985, duration: 2.2)
        ])
        bodySprite.run(.repeatForever(breathe), withKey: "breathing")

        // 3. Gentle vertical bob
        let bob = SKAction.sequence([
            .moveBy(x: 0, y: 1.5, duration: 2.2),
            .moveBy(x: 0, y: -1.5, duration: 2.2)
        ])
        bodySprite.run(.repeatForever(bob), withKey: "bobbing")

        // 4. Shadow counter-sway — shifts opposite to the character sway
        if let shadow = shadowNode {
            let shadowSway = SKAction.sequence([
                .moveBy(x: -2, y: 0, duration: swayDuration),
                .moveBy(x: 2, y: 0, duration: swayDuration),
            ])
            shadow.run(.repeatForever(shadowSway), withKey: "shadowSway")
        }

        // 5. Highlight drift — light source wanders across the character
        if let highlight = highlightNode {
            let drift = SKAction.sequence([
                .moveBy(x: 8, y: 3, duration: 4.0),
                .moveBy(x: -5, y: -6, duration: 3.5),
                .moveBy(x: -3, y: 3, duration: 3.0),
            ])
            highlight.run(.repeatForever(drift), withKey: "highlightDrift")

            // Subtle pulse of the highlight opacity
            let pulse = SKAction.sequence([
                .fadeAlpha(to: 0.18, duration: 3.0),
                .fadeAlpha(to: 0.08, duration: 3.0),
            ])
            highlight.run(.repeatForever(pulse), withKey: "highlightPulse")
        }
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

    /// Show "Goodbye!" for 3 seconds, then fade out. Calls completion when done.
    func animateDisappear(completion: @escaping () -> Void) {
        stopBreathing()
        goodbyeLabel.run(.fadeIn(withDuration: 0.3))

        run(.sequence([
            .wait(forDuration: 3.0),
            .fadeOut(withDuration: 1.0),
            .run(completion)
        ]))
    }

    func rescale(to newSize: CGFloat) {
        let s = newSize / characterSize
        cardBG.setScale(s)
        bodySprite.setScale(s)
        pillBG.setScale(s)
        statusDot.setScale(s)
        activityWordLabel.setScale(s)
        durationLabel.setScale(s)
        dividerNode.setScale(s)
        folderPrefixLabel.setScale(s)
        projectLabel.setScale(s)
        workingOnPrefix.setScale(s)
        topicLabel.setScale(s)
        statusPrefix.setScale(s)
        statusDetailLabel.setScale(s)
        goodbyeLabel.setScale(s)
        glowNode?.setScale(s)
        shadowNode?.setScale(s)
        highlightNode?.setScale(s)
    }

    // MARK: - Style Support

    /// Build a texture for the given session using the current character style.
    static func makeTexture(sessionID: String, size: CGFloat) -> SKTexture {
        let cgImage: CGImage?
        switch CharacterStyle.current {
        case .kawaii:
            cgImage = CharacterGenerator.generate(sessionID: sessionID, size: size)
        case .starwars:
            cgImage = StarWarsCharacterGenerator.generate(sessionID: sessionID, size: size)
        case .demonslayer:
            cgImage = DemonSlayerCharacterGenerator.generate(sessionID: sessionID, size: size)
        case .onepiece:
            cgImage = OnePieceCharacterGenerator.generate(sessionID: sessionID, size: size)
        case .dragonball:
            cgImage = DragonBallCharacterGenerator.generate(sessionID: sessionID, size: size)
        case .theoffice:
            cgImage = OfficeCharacterGenerator.generate(sessionID: sessionID, size: size)
        case .marvel:
            cgImage = MarvelCharacterGenerator.generate(sessionID: sessionID, size: size)
        }
        let texture: SKTexture
        if let img = cgImage {
            texture = SKTexture(cgImage: img)
        } else {
            texture = SKTexture()
        }
        texture.filteringMode = CharacterStyle.current == .kawaii ? .nearest : .linear
        return texture
    }

    /// Regenerate the body sprite texture and 3D effect nodes after a style change.
    func regenerateTexture() {
        let texture = Self.makeTexture(sessionID: sessionID, size: characterSize)
        bodySprite.texture = texture

        // Restart animations for the new style
        stopBreathing()

        // Remove old office 3D nodes
        shadowNode?.removeFromParent()
        shadowNode = nil
        highlightNode?.removeFromParent()
        highlightNode = nil

        // Add office 3D nodes if switching to office style
        if CharacterStyle.current != .kawaii {
            let cardH = characterSize * 2.6
            let spriteY = cardH * 0.22
            let shadow = Self.makeShadowNode(size: characterSize, spriteY: spriteY)
            insertChild(shadow, at: 1)  // after cardBG, before bodySprite
            shadowNode = shadow

            let highlight = Self.makeHighlightNode(size: characterSize, spriteY: spriteY)
            // Insert after bodySprite
            let spriteIndex = children.firstIndex(of: bodySprite).map { $0 + 1 } ?? 2
            insertChild(highlight, at: spriteIndex)
            highlightNode = highlight
        }

        // Reset bodySprite rotation/position offset from office sway
        bodySprite.zRotation = 0

        startBreathing()
    }

    // MARK: - Office 3D Node Factories

    /// Elliptical shadow beneath the character that shifts with sway.
    private static func makeShadowNode(size: CGFloat, spriteY: CGFloat) -> SKSpriteNode {
        let shadowW = size * 0.6
        let shadowH = size * 0.12
        let pixW = Int(shadowW * 2)
        let pixH = Int(shadowH * 2)

        guard let ctx = CGContext(
            data: nil, width: pixW, height: pixH, bitsPerComponent: 8,
            bytesPerRow: pixW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return SKSpriteNode()
        }

        // Soft elliptical shadow via radial gradient
        let colors: [CGFloat] = [0, 0, 0, 0.25,  0, 0, 0, 0]
        let locations: [CGFloat] = [0, 1]
        if let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                      colorComponents: colors, locations: locations, count: 2) {
            ctx.drawRadialGradient(gradient,
                                   startCenter: CGPoint(x: pixW / 2, y: pixH / 2), startRadius: 0,
                                   endCenter: CGPoint(x: pixW / 2, y: pixH / 2), endRadius: CGFloat(pixW) / 2,
                                   options: [])
        }

        guard let cgImage = ctx.makeImage() else { return SKSpriteNode() }
        let texture = SKTexture(cgImage: cgImage)
        let node = SKSpriteNode(texture: texture, size: CGSize(width: shadowW, height: shadowH))
        node.position = CGPoint(x: 0, y: spriteY - size * 0.48)
        node.zPosition = -1.8  // between card bg and body sprite
        node.alpha = 0.5
        return node
    }

    /// Semi-transparent radial highlight that drifts to simulate a moving light source.
    private static func makeHighlightNode(size: CGFloat, spriteY: CGFloat) -> SKSpriteNode {
        let hlSize = size * 0.7
        let pix = Int(hlSize * 2)

        guard let ctx = CGContext(
            data: nil, width: pix, height: pix, bitsPerComponent: 8,
            bytesPerRow: pix * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return SKSpriteNode()
        }

        // Soft white radial glow
        let colors: [CGFloat] = [1, 1, 1, 0.5,  1, 1, 1, 0]
        let locations: [CGFloat] = [0, 1]
        if let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                      colorComponents: colors, locations: locations, count: 2) {
            let center = CGPoint(x: pix / 2, y: pix / 2)
            ctx.drawRadialGradient(gradient,
                                   startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: CGFloat(pix) / 2,
                                   options: [])
        }

        guard let cgImage = ctx.makeImage() else { return SKSpriteNode() }
        let texture = SKTexture(cgImage: cgImage)
        let node = SKSpriteNode(texture: texture, size: CGSize(width: hlSize, height: hlSize))
        node.position = CGPoint(x: -size * 0.15, y: spriteY + size * 0.15)
        node.zPosition = 0.5  // just above body sprite
        node.alpha = 0.12
        node.blendMode = .add  // additive blending for natural light effect
        return node
    }
}
