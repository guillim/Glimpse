// Glimpse/SessionMonitor.swift
import Foundation

/// Monitors active Claude Code sessions by scanning ~/.claude/ JSONL log files.
/// Polls every 5 seconds and notifies a delegate of session changes.
final class SessionMonitor {

    /// Activity state for a single Claude Code session.
    enum Activity: Equatable {
        case reading    // Agent is reading files (Read, Glob, Grep tools)
        case writing    // Agent is editing/creating files (Edit, Write tools)
        case running    // Agent is running shell commands (Bash tool)
        case thinking   // Agent is reasoning/planning (text output, no tool_use)
        case spawning   // Agent is launching subagents (Agent tool)
        case searching  // Agent is searching the web (WebSearch, WebFetch tools)
        case asking     // Agent asked the user a question (end_turn with question mark or AskUserQuestion)
        case done       // Agent finished its task (end_turn, no question)
        case sleeping   // Active but idle
    }

    /// Snapshot of a discovered session.
    struct Session: Equatable {
        let id: String            // JSONL filename (UUID)
        let projectName: String   // Extracted from parent directory name ("dir: background")
        let projectDirName: String // Raw encoded dir name for path reconstruction
        let activity: Activity
        let topic: String         // Short summary of current goal (from last user message)
        let lastOutput: String    // Last few lines of assistant output (for live log bubble)
        let lastModified: Date
        /// How long (in seconds) the session has been idle (0 when actively producing output).
        let idleDuration: TimeInterval

        /// The tty device path of the claude process for this session (e.g. "/dev/ttys004").
        /// Used for iTerm2 tab focusing. Nil if we couldn't match.
        let tty: String?

        /// Reconstruct the real project path from the encoded directory name.
        /// "-Users-gui-github-background" → "/Users/gui/github/background"
        var projectPath: String {
            "/" + projectDirName.split(separator: "-").joined(separator: "/")
        }

        static func == (lhs: Session, rhs: Session) -> Bool {
            lhs.id == rhs.id && lhs.activity == rhs.activity && lhs.topic == rhs.topic
        }
    }

    /// Called on the main thread when sessions change.
    var onUpdate: (([Session]) -> Void)?

    private var timer: Timer?

    /// Cache: sessionID → (fileSize, lastResult) to skip re-parsing unchanged files.
    /// Confined to `scanQueue` — only accessed from background scans.
    private var scanCache: [String: (fileSize: UInt64, result: ScanResult)] = [:]

    /// Serial queue for file I/O and JSON parsing — keeps the main thread free.
    private let scanQueue = DispatchQueue(label: "com.glimpse.session-monitor", qos: .utility)

    /// Base directory for Claude Code projects.
    private let claudeProjectsDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/projects", isDirectory: true)
    }()

    /// Start polling every 2 seconds.
    func start() {
        stop()
        // Fire immediately, then every 2s.
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    /// Stop polling.
    func stop() {
        timer?.invalidate()
        timer = nil
        scanQueue.async { [weak self] in
            self?.scanCache.removeAll()
        }
    }

    /// One scan cycle: file I/O runs on background queue, callback on main.
    private func scan() {
        scanQueue.async { [weak self] in
            guard let self = self else { return }
            let sessions = self.discoverSessions()
            DispatchQueue.main.async {
                self.onUpdate?(sessions)
            }
        }
    }

    /// Discover all active sessions across all projects.
    private func discoverSessions() -> [Session] {
        let fm = FileManager.default

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: claudeProjectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        var sessions: [Session] = []
        let now = Date()

        // Build map of active sessions from the PID registry (~/.claude/sessions/*.json).
        // Includes PID, tty, and cwd for each running session.
        let sessionProcesses = Self.activeSessionProcesses()
        let activeSessionIDs = Set(sessionProcesses.keys)

        for dirURL in projectDirs {
            let isDir = (try? dirURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if !isDir {
                continue
            }

            // Skip "memory" directories
            if dirURL.lastPathComponent == "memory" { continue }

            let projectName = Self.extractProjectName(from: dirURL.lastPathComponent)

            // Depth-1 scan: only files directly inside the project directory are listed here.
            // Subagent sessions live in subagents/ subdirectories and are naturally excluded
            // by this depth-1 scan. The .jsonl extension filter below handles any remaining
            // non-session entries (e.g. bare directories at depth 1).
            guard let files = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else {
                continue
            }

            for fileURL in files {
                // Extension filter: excludes directories (subagents/) and non-JSONL files.
                guard fileURL.pathExtension == "jsonl" else { continue }

                guard let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = attrs.contentModificationDate else { continue }

                let age = now.timeIntervalSince(modified)

                let sessionID = fileURL.deletingPathExtension().lastPathComponent

                // Only show sessions with a running Claude process.
                guard activeSessionIDs.contains(sessionID) else { continue }

                // Skip re-parsing if file size hasn't changed since last scan.
                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(UInt64.init) ?? 0
                let result: ScanResult
                if let cached = scanCache[sessionID], cached.fileSize == fileSize {
                    result = cached.result
                } else {
                    result = Self.classifyActivityAndTopic(fileURL: fileURL, lastModified: modified, now: now)
                    scanCache[sessionID] = (fileSize: fileSize, result: result)
                }

                sessions.append(Session(
                    id: sessionID,
                    projectName: projectName,
                    projectDirName: dirURL.lastPathComponent,
                    activity: result.activity,
                    topic: result.topic,
                    lastOutput: result.lastOutput,
                    lastModified: modified,
                    idleDuration: age,
                    tty: sessionProcesses[sessionID]?.tty
                ))
            }
        }

        // Prune cache entries for sessions no longer present.
        let currentIDs = Set(sessions.map(\.id))
        scanCache = scanCache.filter { currentIDs.contains($0.key) }

        return sessions
    }

    /// Extract human-readable project name from encoded directory name.
    /// "-Users-gui-github-background" → "dir: background"
    static func extractProjectName(from dirName: String) -> String {
        let components = dirName.split(separator: "-").map(String.init)
        let name = components.last ?? dirName
        return "dir: \(name)"
    }

    /// Truncate output to fit in the bubble: max N lines, max M chars.
    static func truncateOutput(_ text: String, maxLines: Int, maxChars: Int) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(maxLines)
        var result = lines.joined(separator: "\n")
        if result.count > maxChars {
            result = String(result.suffix(maxChars - 3))
            // Trim to word boundary
            if let spaceIdx = result.firstIndex(of: " ") {
                result = "..." + String(result[spaceIdx...])
            }
        }
        return result
    }

    /// Extract a short topic (1-3 words) from the user's message.
    /// Takes the first few meaningful words, stripping common prefixes.
    static func extractTopic(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Take first line only
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed

        // Split into words, take first 3 meaningful ones
        let words = firstLine.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .prefix(4)

        let topic = words.joined(separator: " ")

        // Cap at 30 chars
        if topic.count > 30 {
            return String(topic.prefix(27)) + "..."
        }
        return topic
    }

    /// Read ~/.claude/sessions/*.json to get session IDs of currently running Claude processes.
    /// Info about a running Claude session process.
    struct SessionProcess {
        let pid: Int
        let sessionId: String
        let cwd: String
        let tty: String?  // e.g. "/dev/ttys004"
    }

    /// Read ~/.claude/sessions/*.json to get running session PIDs, IDs, and resolve their ttys.
    private static func activeSessionProcesses() -> [String: SessionProcess] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessionsDir = home.appendingPathComponent(".claude/sessions", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [:] }

        var result: [String: SessionProcess] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionId = json["sessionId"] as? String,
                  let pid = json["pid"] as? Int,
                  let cwd = json["cwd"] as? String else { continue }

            // Resolve tty from PID via ps
            let tty = resolveTty(pid: pid)

            result[sessionId] = SessionProcess(pid: pid, sessionId: sessionId, cwd: cwd, tty: tty)
        }
        return result
    }

    /// Get active session IDs (convenience wrapper).
    private static func activeSessionIDs() -> Set<String> {
        Set(activeSessionProcesses().keys)
    }

    /// Resolve the tty of a process via ps.
    private static func resolveTty(pid: Int) -> String? {
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
        return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
    }

    struct ScanResult {
        let activity: Activity
        let topic: String
        let lastOutput: String
    }

    /// Read last ~20 lines of a JSONL file, classify activity, extract topic, and last output.
    /// Uses FileHandle to read only the tail of potentially large files.
    static func classifyActivityAndTopic(fileURL: URL, lastModified: Date, now: Date) -> ScanResult {
        let empty = ScanResult(activity: .sleeping, topic: "", lastOutput: "")

        // Read only the last ~32KB to avoid loading multi-MB session logs entirely.
        let tailBytes = 32 * 1024
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return empty }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let readOffset = fileSize > UInt64(tailBytes) ? fileSize - UInt64(tailBytes) : 0
        handle.seek(toFileOffset: readOffset)
        let data = handle.availableData
        guard let content = String(data: data, encoding: .utf8) else {
            return empty
        }

        // Get last ~20 non-empty lines (more for topic extraction)
        let lines = content.components(separatedBy: .newlines)
            .suffix(30)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(20)

        var activity: Activity = .sleeping
        var topic: String = ""
        var lastOutput: String = ""

        // Walk backwards to find the most recent meaningful message
        for line in lines.reversed() {
            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String

            // Extract topic from the most recent user message (text, not tool results)
            if topic.isEmpty, type == "user",
               let message = json["message"] as? [String: Any],
               let msgContent = message["content"] as? String {
                topic = Self.extractTopic(from: msgContent)
            }

            // Also handle user messages with role/content structure
            if topic.isEmpty, type == "user",
               let message = json["message"] as? [String: Any],
               message["role"] as? String == "user",
               let msgContent = message["content"] as? String {
                topic = Self.extractTopic(from: msgContent)
            }

            // Extract last assistant text output for the live log bubble
            if lastOutput.isEmpty, type == "assistant",
               let message = json["message"] as? [String: Any],
               let blocks = message["content"] as? [[String: Any]] {
                for block in blocks {
                    if block["type"] as? String == "text",
                       let text = block["text"] as? String,
                       !text.isEmpty {
                        lastOutput = Self.truncateOutput(text, maxLines: 4, maxChars: 200)
                        break
                    }
                }
            }

            // Skip if we already classified activity
            guard activity == .sleeping else { continue }

            // Check for assistant end_turn first — this takes priority over content classification.
            // Distinguish "asking a question" from "finished task".
            if type == "assistant",
               let message = json["message"] as? [String: Any],
               message["stop_reason"] as? String == "end_turn" {
                // Check if the agent is asking a question
                var isAsking = false
                if let blocks = message["content"] as? [[String: Any]] {
                    for block in blocks {
                        // AskUserQuestion tool means it's definitely asking
                        if block["type"] as? String == "tool_use",
                           block["name"] as? String == "AskUserQuestion" {
                            isAsking = true
                            break
                        }
                        // Text ending with "?" suggests a question
                        if block["type"] as? String == "text",
                           let text = block["text"] as? String,
                           text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") {
                            isAsking = true
                        }
                    }
                }
                activity = isAsking ? .asking : .done
                continue
            }

            // Check for assistant message with tool use (active work)
            if type == "assistant",
               let message = json["message"] as? [String: Any],
               let blocks = message["content"] as? [[String: Any]] {

                // Classify by tool_use blocks (priority: Bash > Agent > Web > Write > Read)
                let toolNames = blocks.compactMap { block -> String? in
                    guard block["type"] as? String == "tool_use" else { return nil }
                    return block["name"] as? String
                }

                if !toolNames.isEmpty {
                    let toolSet = Set(toolNames)
                    if toolSet.contains("Bash") {
                        activity = .running
                    } else if toolSet.contains("Agent") {
                        activity = .spawning
                    } else if !toolSet.isDisjoint(with: ["WebSearch", "WebFetch"]) {
                        activity = .searching
                    } else if !toolSet.isDisjoint(with: ["Edit", "Write"]) {
                        activity = .writing
                    } else if !toolSet.isDisjoint(with: ["Read", "Glob", "Grep"]) {
                        activity = .reading
                    } else {
                        activity = .thinking
                    }
                } else {
                    // Text-only message, no tool_use → thinking
                    let hasText = blocks.contains { $0["type"] as? String == "text" }
                    if hasText {
                        activity = .thinking
                    }
                }
            }

            // User message — session is active, agent is probably processing
            if activity == .sleeping, type == "user" {
                activity = .thinking
            }
        }

        return ScanResult(activity: activity, topic: topic, lastOutput: lastOutput)
    }
}
