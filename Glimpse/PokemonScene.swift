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

        // Handle stale sessions — treat them as departing
        for session in sessions where session.isStale {
            triggerDeparture(for: session.id)
        }

        // Add new or update existing sessions
        let nonStaleSessions = sessions.filter { !$0.isStale }
        let charSize = characterSize(for: nonStaleSessions.count)
        for session in nonStaleSessions {
            guard !departingNodes.contains(session.id) else { continue }
            if let existing = characterNodes[session.id] {
                // Update activity, topic, and live log
                existing.updateActivity(session.activity)
                existing.updateTopic(session.topic)
                existing.updateLastOutput(session.lastOutput)
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

    // MARK: - Terminal Activation

    /// Find and bring to front a terminal window running in the session's project directory.
    /// Uses tty-based cwd matching: gets each terminal session's tty, checks if the process
    /// on that tty has a working directory matching the project path.
    private func activateTerminal(for sessionID: String) {
        guard let projectPath = sessionPaths[sessionID] else { return }
        NSLog("[Glimpse] activateTerminal: looking for project path '%@'", projectPath)

        // Try iTerm2 first (user's primary terminal), then Terminal.app
        if activateITermByCwd(projectPath: projectPath) {
            NSLog("[Glimpse] Activated iTerm2 session for '%@'", projectPath)
        } else if activateTerminalAppByCwd(projectPath: projectPath) {
            NSLog("[Glimpse] Activated Terminal.app window for '%@'", projectPath)
        } else {
            NSLog("[Glimpse] No terminal found for '%@'", projectPath)
        }
    }

    /// Find an iTerm2 session whose tty process has cwd matching the project path.
    private func activateITermByCwd(projectPath: String) -> Bool {
        // Get all iTerm2 session ttys, check cwd of each via lsof, activate matching one.
        let script = """
        tell application "System Events"
            if not (exists process "iTerm2") then return ""
        end tell
        tell application "iTerm2"
            set result to ""
            set wc to count of windows
            repeat with i from 1 to wc
                set tc to count of tabs of window i
                repeat with j from 1 to tc
                    set sc to count of sessions of tab j of window i
                    repeat with k from 1 to sc
                        set s to session k of tab j of window i
                        set t to tty of s
                        set result to result & t & ":" & i & ":" & j & ":" & k & linefeed
                    end repeat
                end repeat
            end repeat
            return result
        end tell
        """

        guard let ttysScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        let result = ttysScript.executeAndReturnError(&error)
        if error != nil { return false }

        let ttysString = result.stringValue ?? ""
        let entries = ttysString.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for entry in entries {
            let parts = entry.components(separatedBy: ":")
            guard parts.count >= 4, let tty = parts.first else { continue }

            // Check if a process on this tty has cwd matching our project
            if ttyHasCwd(tty: tty, projectPath: projectPath) {
                let winIdx = parts[1]
                let tabIdx = parts[2]
                NSLog("[Glimpse] Found match on %@ (window %@, tab %@)", tty, winIdx, tabIdx)

                // Activate this window and tab
                let activateScript = """
                tell application "iTerm2"
                    set index of window \(winIdx) to 1
                    select tab \(tabIdx) of window 1
                    activate
                end tell
                """
                _ = runAppleScript(activateScript)
                return true
            }
        }
        return false
    }

    /// Check if any process on the given tty has a cwd matching the project path.
    private func ttyHasCwd(tty: String, projectPath: String) -> Bool {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["+D", tty, "-Fn"]  // This won't work well, use different approach
        // Instead: find PIDs attached to this tty, then check their cwd
        let lsofPipe = Pipe()
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = [tty]
        lsof.standardOutput = lsofPipe
        lsof.standardError = FileHandle.nullDevice
        do {
            try lsof.run()
            lsof.waitUntilExit()
        } catch { return false }

        let data = lsofPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }

        // Extract PIDs from lsof output
        var pids = Set<String>()
        for line in output.components(separatedBy: .newlines) {
            let cols = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if cols.count >= 2, cols[0] != "COMMAND" {
                pids.insert(cols[1])
            }
        }

        // Check cwd of each PID
        for pid in pids {
            let cwdPipe = Pipe()
            let cwdProc = Process()
            cwdProc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            cwdProc.arguments = ["-p", pid, "-Fn"]
            cwdProc.standardOutput = cwdPipe
            cwdProc.standardError = FileHandle.nullDevice
            do {
                try cwdProc.run()
                cwdProc.waitUntilExit()
            } catch { continue }

            let cwdData = cwdPipe.fileHandleForReading.readDataToEndOfFile()
            guard let cwdOutput = String(data: cwdData, encoding: .utf8) else { continue }

            // lsof -Fn output: lines starting with 'n' are file names
            // Look for 'cwd' type followed by the path
            let lines = cwdOutput.components(separatedBy: .newlines)
            var isCwd = false
            for line in lines {
                if line == "fcwd" { isCwd = true; continue }
                if isCwd && line.hasPrefix("n") {
                    let path = String(line.dropFirst())
                    if path == projectPath || projectPath.hasPrefix(path) || path.hasPrefix(projectPath) {
                        return true
                    }
                    isCwd = false
                }
            }
        }
        return false
    }

    /// Search Terminal.app windows by checking tty cwd.
    private func activateTerminalAppByCwd(projectPath: String) -> Bool {
        let dirName = (projectPath as NSString).lastPathComponent
        let script = """
        tell application "System Events"
            if not (exists process "Terminal") then return false
        end tell
        tell application "Terminal"
            set windowCount to count of windows
            repeat with i from 1 to windowCount
                set winName to name of window i
                if winName contains "\(dirName)" then
                    set frontmost to true
                    set index of window i to 1
                    activate
                    return true
                end if
            end repeat
        end tell
        return false
        """
        return runAppleScript(script)
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
}
