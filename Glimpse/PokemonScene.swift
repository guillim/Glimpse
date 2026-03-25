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

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .black
        addChild(emptyLabel)
        emptyLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        print("[PokemonScene] didMove — size: \(size)")

        sessionMonitor.onUpdate = { [weak self] sessions in
            print("[PokemonScene] onUpdate — \(sessions.count) sessions found")
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

        // Remove departed sessions (no longer in active list)
        for id in existingIDs.subtracting(activeIDs) {
            triggerDeparture(for: id)
        }

        // Handle stale sessions — treat them as departing
        for session in sessions where session.isStale {
            triggerDeparture(for: session.id)
        }

        // Add new or update existing sessions
        let nonStaleSessions = sessions.filter { !$0.isStale }
        let charSize = characterSize(for: nonStaleSessions.count)
        print("[PokemonScene] scene.size=\(size), charSize=\(charSize), nonStale=\(nonStaleSessions.count)")
        for session in nonStaleSessions {
            guard !departingNodes.contains(session.id) else { continue }
            if let existing = characterNodes[session.id] {
                // Update activity
                existing.updateActivity(session.activity)
            } else {
                // New session — create character
                print("[PokemonScene] Creating character for session \(session.id.prefix(8))... project=\(session.projectName)")
                let node = CharacterNode(
                    sessionID: session.id,
                    projectName: session.projectName,
                    size: charSize
                )
                node.updateActivity(session.activity)
                node.animateAppear()
                addChild(node)
                characterNodes[session.id] = node
                print("[PokemonScene] Character node position=\(node.position), children=\(node.children.count)")
            }
        }

        // Update empty state
        let visibleCount = characterNodes.keys.filter { !departingNodes.contains($0) }.count
        emptyLabel.isHidden = visibleCount > 0

        relayout()
    }

    /// Trigger goodbye animation and removal for a session ID, if not already departing.
    private func triggerDeparture(for id: String) {
        guard !departingNodes.contains(id) else { return }
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
        guard count > 0 else {
            print("[PokemonScene] relayout: no active nodes")
            return
        }
        print("[PokemonScene] relayout: \(count) nodes, scene.size=\(size)")

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
