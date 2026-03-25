// Glimpse/PokemonScene.swift
import SpriteKit

/// SpriteKit scene displaying Pokemon-styled characters for active Claude sessions.
final class PokemonScene: SKScene {

    private let sessionMonitor = SessionMonitor()
    private var characterNodes: [String: CharacterNode] = [:]  // sessionID → node
    private var sessionPaths: [String: String] = [:]  // sessionID → project path
    private var departingNodes: Set<String> = []  // sessions currently fading out

    /// Empty-state label shown when no sessions are active.
    private let emptyLabel: SKLabelNode = {
        let label = SKLabelNode(fontNamed: "Menlo")
        label.text = "No Claude sessions active — start one to see your agent!"
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

    // Debug: gaze dot visualization
    private let gazeDot: SKShapeNode = {
        let dot = SKShapeNode(circleOfRadius: 3)
        dot.fillColor = .init(red: 1, green: 0, blue: 0, alpha: 0.4)
        dot.strokeColor = .clear
        dot.lineWidth = 0
        dot.zPosition = 100
        return dot
    }()

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .black
        addChild(emptyLabel)
        emptyLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(gazeDot)

        sessionMonitor.onUpdate = { [weak self] sessions in
            self?.handleSessionUpdate(sessions)
        }
        sessionMonitor.start()
    }

    override func willMove(from view: SKView) {
        sessionMonitor.stop()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        emptyLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        relayout()
    }

    // MARK: - Session Updates

    private func handleSessionUpdate(_ sessions: [SessionMonitor.Session]) {
        let activeIDs = Set(sessions.map(\.id))
        let existingIDs = Set(characterNodes.keys)

        // Remove departed sessions (no longer in active list)
        for id in existingIDs.subtracting(activeIDs) {
            triggerDeparture(for: id)
        }

        // Add new or update existing sessions
        let charSize = characterSize(for: sessions.count)
        for session in sessions {
            guard !departingNodes.contains(session.id) else { continue }
            if let existing = characterNodes[session.id] {
                // Update activity, topic, live log, and idle duration
                existing.updateActivity(session.activity)
                existing.updateTopic(session.topic)
                existing.updateLastOutput(session.lastOutput)
                existing.updateIdleDuration(session.idleDuration)
            } else {
                // New session — create character
                let node = CharacterNode(
                    sessionID: session.id,
                    projectName: session.projectName,
                    size: charSize
                )
                node.updateActivity(session.activity)
                node.updateTopic(session.topic)
                node.updateLastOutput(session.lastOutput)
                node.updateIdleDuration(session.idleDuration)
                sessionPaths[session.id] = session.projectPath
                node.onActivate = { [weak self] in
                    self?.activateTerminal(for: session.id)
                }
                node.animateAppear()
                addChild(node)
                characterNodes[session.id] = node
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
                self?.sessionPaths.removeValue(forKey: id)
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
            return
        }

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

        // Update gaze dot
        gazeDot.position = gazePoint

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

    // MARK: - App Activation

    /// Find the application that hosts the Claude session and bring it to front.
    /// Also focuses the specific window/tab if running in iTerm2.
    private func activateTerminal(for sessionID: String) {
        guard let projectPath = sessionPaths[sessionID] else { return }

        // Find a "claude" process whose cwd matches this project
        guard let match = findClaudeProcess(forProjectPath: projectPath) else {
            NSLog("[Glimpse] No app found for '%@'", projectPath)
            return
        }

        // Activate the GUI app
        if let app = NSRunningApplication(processIdentifier: match.appPID) {
            NSLog("[Glimpse] Activating '%@' (pid %d) for '%@'",
                  app.localizedName ?? "unknown", match.appPID, projectPath)
            app.activate(options: [.activateAllWindows])

            // If it's iTerm2, also focus the specific window and tab via tty matching
            if app.bundleIdentifier == "com.googlecode.iterm2", let tty = match.tty {
                focusITermTab(tty: tty)
            }
        }
    }

    /// Result of finding a claude process.
    private struct ProcessMatch {
        let claudePID: pid_t
        let appPID: pid_t
        let tty: String?  // e.g. "/dev/ttys004"
    }

    /// Find a "claude" process with cwd matching the project path,
    /// then walk up the parent chain to find the GUI application PID.
    /// Also captures the tty for iTerm2 tab focusing.
    private func findClaudeProcess(forProjectPath projectPath: String) -> ProcessMatch? {
        let pgrepPipe = Pipe()
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", "claude"]
        pgrep.standardOutput = pgrepPipe
        pgrep.standardError = FileHandle.nullDevice
        do { try pgrep.run(); pgrep.waitUntilExit() } catch { return nil }

        let pgrepData = pgrepPipe.fileHandleForReading.readDataToEndOfFile()
        guard let pgrepOutput = String(data: pgrepData, encoding: .utf8) else { return nil }

        let claudePIDs = pgrepOutput.components(separatedBy: .newlines)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }

        for pid in claudePIDs {
            if let cwd = getCwd(pid: pid), cwd == projectPath {
                if let appPID = findParentApp(pid: pid) {
                    let tty = getTty(pid: pid)
                    return ProcessMatch(claudePID: pid, appPID: appPID, tty: tty)
                }
            }
        }
        return nil
    }

    /// Focus the iTerm2 window and tab that owns the given tty.
    private func focusITermTab(tty: String) {
        let script = """
        tell application "iTerm2"
            set wc to count of windows
            repeat with i from 1 to wc
                set tc to count of tabs of window i
                repeat with j from 1 to tc
                    set sc to count of sessions of tab j of window i
                    repeat with k from 1 to sc
                        set s to session k of tab j of window i
                        if tty of s is "\(tty)" then
                            select tab j of window i
                            set index of window i to 1
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        if runAppleScript(script) {
            NSLog("[Glimpse] Focused iTerm2 tab with tty %@", tty)
        }
    }

    /// Get the controlling tty of a process (e.g. "/dev/ttys004").
    private func getTty(pid: pid_t) -> String? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-o", "tty=", "-p", "\(pid)"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run(); proc.waitUntilExit() } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let tty = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tty.isEmpty, tty != "??" else { return nil }
        // ps returns "ttys004", iTerm expects "/dev/ttys004"
        return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
    }

    private func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let err = error {
            NSLog("[Glimpse] AppleScript error: %@", err.description)
            return false
        }
        return result.booleanValue
    }

    /// Get the current working directory of a process.
    private func getCwd(pid: pid_t) -> String? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // IMPORTANT: -a ANDs the filters. Without it, -p and -d are ORed (returns all processes' cwd).
        proc.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run(); proc.waitUntilExit() } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        // Parse lsof -Fn output: 'n' prefix lines are paths
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("n/") {
                return String(line.dropFirst())
            }
        }
        return nil
    }

    /// Walk up the process parent chain to find a GUI application.
    /// Returns the PID of the first ancestor that is a running NSRunningApplication.
    private func findParentApp(pid: pid_t) -> pid_t? {
        var currentPID = pid
        var visited = Set<pid_t>()

        while currentPID > 1 && !visited.contains(currentPID) {
            visited.insert(currentPID)

            // Check if this PID is a GUI app
            if NSRunningApplication(processIdentifier: currentPID) != nil {
                return currentPID
            }

            // Get parent PID
            guard let ppid = getParentPID(currentPID) else { break }
            currentPID = ppid
        }
        return nil
    }

    /// Get the parent PID of a process.
    private func getParentPID(_ pid: pid_t) -> pid_t? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-o", "ppid=", "-p", "\(pid)"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run(); proc.waitUntilExit() } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        return Int32(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
