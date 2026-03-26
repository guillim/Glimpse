// Glimpse/AgentMonitorScene.swift
import SpriteKit
import AppKit

/// SpriteKit scene displaying characters for active Claude Code sessions.
final class AgentMonitorScene: SKScene {

    private let sessionMonitor = SessionMonitor()
    private var characterNodes: [String: CharacterNode] = [:]  // sessionID → node
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

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .clear
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

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        emptyLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        relayout()
    }

    // MARK: - Session Updates

    private func handleSessionUpdate(_ sessions: [SessionMonitor.Session]) {
        let activeIDs = Set(sessions.map(\.id))
        let existingIDs = Set(characterNodes.keys)

        for id in existingIDs.subtracting(activeIDs) {
            triggerDeparture(for: id)
        }

        let charSize = characterSize(for: sessions.count)
        for session in sessions {
            guard !departingNodes.contains(session.id) else { continue }
            if let existing = characterNodes[session.id] {
                existing.updateActivity(session.activity)
                existing.updateTopics(session.topics)
                existing.updateIdleDuration(session.idleDuration)
            } else {
                let node = CharacterNode(
                    sessionID: session.id,
                    projectName: session.projectName,
                    size: charSize
                )
                node.updateActivity(session.activity)
                node.updateTopics(session.topics)
                node.updateIdleDuration(session.idleDuration)
                node.animateAppear()
                addChild(node)
                characterNodes[session.id] = node
            }
        }

        let visibleCount = characterNodes.keys.filter { !departingNodes.contains($0) }.count
        emptyLabel.isHidden = visibleCount > 0

        relayout()
    }

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

    // MARK: - Click Interaction

    /// Find the CharacterNode at the given scene point, if any.
    func characterNode(at point: CGPoint) -> CharacterNode? {
        for (id, node) in characterNodes where !departingNodes.contains(id) {
            let local = convert(point, to: node)
            if node.cardBounds.contains(local) {
                return node
            }
        }
        return nil
    }

    /// Resolve a session ID to its parent GUI app and activate it.
    func activateAppForSession(_ sessionID: String) {
        NSLog("[Glimpse] activateAppForSession: %@", sessionID)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let pid = Self.findSessionPID(sessionID) else {
                NSLog("[Glimpse] no PID"); return
            }
            guard let app = Self.findParentGUIApp(pid: pid) else {
                NSLog("[Glimpse] no parent app"); return
            }
            NSLog("[Glimpse] activating %@ pid=%d", app.bundleIdentifier ?? "?", pid)

            // Select the right tab via AppleScript, then activate the app
            if let tty = Self.resolveTty(pid: pid) {
                let bundleID = app.bundleIdentifier ?? ""
                if bundleID == "com.googlecode.iterm2" {
                    Self.selectITermTab(tty: tty)
                } else if bundleID == "com.apple.Terminal" {
                    Self.selectTerminalTab(tty: tty)
                }
            }

            DispatchQueue.main.async {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }

    /// Find the PID of a Claude session from ~/.claude/sessions/*.json.
    private static func findSessionPID(_ sessionID: String) -> Int? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessionsDir = home.appendingPathComponent(".claude/sessions", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return nil }

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sid = json["sessionId"] as? String,
                  sid == sessionID,
                  let pid = json["pid"] as? Int else { continue }
            return pid
        }
        return nil
    }

    /// Resolve the controlling tty for a process by walking up the tree.
    /// Returns a tty name like "ttys003".
    private static func resolveTty(pid: Int) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "tty=", "-p", "\(pid)"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let tty = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tty, !tty.isEmpty, tty != "??" else { return nil }
        return tty
    }

    /// Select the right tab in iTerm2 by tty. No Space switching — just tab selection.
    private static func selectITermTab(tty: String) {
        let devTty = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(devTty)" then
                            select t
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        runAppleScript(script)
    }

    /// Select the right tab in Terminal.app by tty.
    private static func selectTerminalTab(tty: String) {
        let devTty = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(devTty)" then
                        set selected tab of w to t
                    end if
                end repeat
            end repeat
        end tell
        """
        runAppleScript(script)
    }

    /// Run an AppleScript via osascript using stdin.
    @discardableResult
    private static func runAppleScript(_ source: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            inputPipe.fileHandleForWriting.write(source.data(using: .utf8)!)
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Walk up the process tree from a PID to find the first GUI application.
    private static func findParentGUIApp(pid: Int) -> NSRunningApplication? {
        var current = pid
        var visited = Set<Int>()

        while current > 1 {
            guard !visited.contains(current) else { break }
            visited.insert(current)

            if let app = NSRunningApplication(processIdentifier: pid_t(current)),
               app.activationPolicy == .regular {
                return app
            }

            guard let ppid = parentPID(of: current) else { break }
            current = ppid
        }
        return nil
    }

    /// Get the parent PID of a process using sysctl.
    private static func parentPID(of pid: Int) -> Int? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        let ppid = Int(info.kp_eproc.e_ppid)
        return ppid > 0 ? ppid : nil
    }

    // MARK: - Adaptive Grid Layout

    private func relayout() {
        let activeNodes = characterNodes.values.filter { !departingNodes.contains($0.sessionID) }
        let count = activeNodes.count
        guard count > 0 else { return }

        let cols = columns(for: count)
        let rows = Int(ceil(Double(count) / Double(cols)))

        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rows)

        let sorted = activeNodes.sorted { $0.sessionID < $1.sessionID }

        for (i, node) in sorted.enumerated() {
            let row = i / cols
            let col = i % cols

            let itemsInRow = min(cols, count - row * cols)
            let rowOffsetX = (size.width - CGFloat(itemsInRow) * cellW) / 2

            let x = rowOffsetX + CGFloat(col) * cellW + cellW / 2
            let totalGridH = CGFloat(rows) * cellH
            let gridOffsetY = (size.height - totalGridH) / 2
            let y = size.height - gridOffsetY - CGFloat(row) * cellH - cellH / 2

            let targetPos = CGPoint(x: x, y: y)

            node.removeAction(forKey: "reposition")
            node.run(.move(to: targetPos, duration: 0.3), withKey: "reposition")
        }

        let newSize = characterSize(for: count)
        for node in sorted {
            node.rescale(to: newSize)
        }
    }
}
