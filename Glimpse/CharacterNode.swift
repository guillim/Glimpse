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
        let spriteY = cardH * 0.22
        bodySprite.position = CGPoint(x: 0, y: spriteY)

        // Status row: colored pill with glowing dot + uppercase text
        let statusY = spriteY - size * 0.5 - size * 0.15
        let pillW = size * 0.85
        let pillH = size * 0.22
        let pillR = pillH / 2

        pillBG = SKShapeNode(rectOf: CGSize(width: pillW, height: pillH), cornerRadius: pillR)
        pillBG.fillColor = .init(red: 0.39, green: 0.39, blue: 0.47, alpha: 0.12)
        pillBG.strokeColor = .init(red: 0.39, green: 0.39, blue: 0.47, alpha: 0.2)
        pillBG.lineWidth = 1
        pillBG.position = CGPoint(x: 0, y: statusY)

        let dotR = max(size * 0.04, 3)
        statusDot = SKShapeNode(circleOfRadius: dotR)
        statusDot.fillColor = .init(red: 0.4, green: 0.4, blue: 0.47, alpha: 1)
        statusDot.strokeColor = .clear
        statusDot.glowWidth = max(size * 0.03, 2)
        statusDot.position = CGPoint(x: -pillW * 0.32, y: statusY)

        activityWordLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        activityWordLabel.text = "IDLE"
        activityWordLabel.fontSize = max(size * 0.11, 8)
        activityWordLabel.fontColor = .init(red: 0.53, green: 0.53, blue: 0.58, alpha: 1)
        activityWordLabel.position = CGPoint(x: size * 0.03, y: statusY)
        activityWordLabel.verticalAlignmentMode = .center
        activityWordLabel.horizontalAlignmentMode = .center

        // Duration label (outside pill, to the right)
        durationLabel = SKLabelNode(fontNamed: "Menlo")
        durationLabel.text = ""
        durationLabel.fontSize = max(size * 0.09, 7)
        durationLabel.fontColor = .init(red: 0.45, green: 0.45, blue: 0.52, alpha: 1)
        durationLabel.position = CGPoint(x: pillW * 0.55 + 4, y: statusY)
        durationLabel.verticalAlignmentMode = .center
        durationLabel.horizontalAlignmentMode = .left

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
        let projectFontSize = max(size * 0.09, 7)
        let projectY = dividerY - size * 0.06

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

        // "working on:" section
        let sectionFontSize = max(size * 0.09, 7)
        let contentFontSize = max(size * 0.09, 7)
        let sectionPadding: CGFloat = 8
        let sectionLeftX = -cardW * 0.5 + sectionPadding
        let sectionMaxWidth = cardW - sectionPadding * 2

        // "working on:" prefix — hidden, kept for node tree compatibility
        let workingOnY = projectY - projectFontSize - 3
        workingOnPrefix = SKLabelNode(fontNamed: "Menlo")
        workingOnPrefix.text = ""
        workingOnPrefix.fontSize = sectionFontSize
        workingOnPrefix.fontColor = .init(red: 0.35, green: 0.35, blue: 0.42, alpha: 1)
        workingOnPrefix.position = CGPoint(x: sectionLeftX, y: workingOnY)
        workingOnPrefix.verticalAlignmentMode = .top
        workingOnPrefix.horizontalAlignmentMode = .left

        // Topic hashtags — single line
        topicLabel = SKLabelNode(fontNamed: "Menlo")
        topicLabel.text = ""
        topicLabel.fontSize = sectionFontSize
        topicLabel.fontColor = .init(red: 0.78, green: 0.72, blue: 0.45, alpha: 1)
        topicLabel.numberOfLines = 1
        topicLabel.preferredMaxLayoutWidth = sectionMaxWidth
        topicLabel.position = CGPoint(x: sectionLeftX, y: workingOnY)
        topicLabel.verticalAlignmentMode = .top
        topicLabel.horizontalAlignmentMode = .left

        // "status:" prefix — hidden, kept for node tree compatibility
        let statusSectionY = workingOnY - sectionFontSize - 3
        statusPrefix = SKLabelNode(fontNamed: "Menlo")
        statusPrefix.text = ""
        statusPrefix.fontSize = sectionFontSize
        statusPrefix.fontColor = .init(red: 0.35, green: 0.35, blue: 0.42, alpha: 1)
        statusPrefix.position = CGPoint(x: sectionLeftX, y: statusSectionY)
        statusPrefix.verticalAlignmentMode = .top
        statusPrefix.horizontalAlignmentMode = .left

        // Status detail — shows last sentence of assistant's last message
        statusDetailLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        statusDetailLabel.text = ""
        statusDetailLabel.fontSize = contentFontSize
        statusDetailLabel.fontColor = .init(red: 0.5, green: 0.5, blue: 0.56, alpha: 1)
        statusDetailLabel.numberOfLines = 5
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
        addChild(bodySprite)
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

        // Show duration outside the pill for standby states
        durationLabel.text = Self.showsDuration(activity) ? (idleDurationText ?? "") : ""

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
    }
}
