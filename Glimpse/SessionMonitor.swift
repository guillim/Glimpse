// Glimpse/SessionMonitor.swift
import Foundation

/// Monitors active Claude Code sessions by scanning ~/.claude/ JSONL log files.
/// Polls every 2 seconds and notifies via callback on session changes.
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
        let projectName: String   // Extracted from parent directory name
        let activity: Activity
        let topics: [String]      // Last up-to-3 user input topics (oldest first)
        let lastModified: Date
        /// How long (in seconds) the session has been idle (0 when actively producing output).
        let idleDuration: TimeInterval

        static func == (lhs: Session, rhs: Session) -> Bool {
            lhs.id == rhs.id && lhs.activity == rhs.activity && lhs.topics == rhs.topics
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

        let activeSessionIDs = Self.activeSessionIDs()

        for dirURL in projectDirs {
            let isDir = (try? dirURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if !isDir { continue }
            if dirURL.lastPathComponent == "memory" { continue }

            let projectName = Self.extractProjectName(from: dirURL.lastPathComponent)

            // Depth-1 scan: subagent sessions in subagents/ subdirectories are naturally excluded.
            guard let files = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else {
                continue
            }

            for fileURL in files {
                guard fileURL.pathExtension == "jsonl" else { continue }

                guard let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = attrs.contentModificationDate else { continue }

                let sessionID = fileURL.deletingPathExtension().lastPathComponent
                guard activeSessionIDs.contains(sessionID) else { continue }

                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(UInt64.init) ?? 0
                let result: ScanResult
                if let cached = scanCache[sessionID], cached.fileSize == fileSize {
                    result = cached.result
                } else {
                    var fresh = Self.classifyActivity(fileURL: fileURL, lastModified: modified, now: now)
                    // Carry forward previous topics when the new scan found none
                    // (assistant output can push user messages out of the tail window)
                    if fresh.topics.isEmpty, let cached = scanCache[sessionID], !cached.result.topics.isEmpty {
                        fresh = ScanResult(activity: fresh.activity, topics: cached.result.topics)
                    }
                    result = fresh
                    scanCache[sessionID] = (fileSize: fileSize, result: result)
                }

                sessions.append(Session(
                    id: sessionID,
                    projectName: projectName,
                    activity: result.activity,
                    topics: result.topics,
                    lastModified: modified,
                    idleDuration: now.timeIntervalSince(modified)
                ))
            }
        }

        // Prune cache entries for sessions no longer present.
        let currentIDs = Set(sessions.map(\.id))
        scanCache = scanCache.filter { currentIDs.contains($0.key) }

        return sessions
    }

    /// Extract human-readable project name from encoded directory name.
    /// "-Users-gui-github-background" → "background"
    static func extractProjectName(from dirName: String) -> String {
        let components = dirName.split(separator: "-").map(String.init)
        return components.last ?? dirName
    }

    // MARK: - Smart Topic Extraction

    /// Filler prefixes to strip (longest first to avoid partial matches).
    private static let fillerPrefixes = [
        "i'd like to", "i want to", "i need to",
        "could you", "would you", "can you",
        "please", "let's", "okay", "hey", "ok", "so"
    ]

    /// Stop words to drop when collecting meaningful words.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "in", "to", "for", "from", "with",
        "on", "at", "of", "by", "is", "are", "was", "it", "that", "this",
        "me", "my", "and", "or", "but", "not", "just", "also", "some", "all"
    ]

    /// Action verbs to anchor topic extraction.
    private static let actionVerbs: Set<String> = [
        "fix", "add", "improve", "refactor", "update", "remove", "create", "implement",
        "build", "change", "move", "rename", "replace", "delete", "write", "make", "set",
        "configure", "enable", "disable", "debug", "test", "check", "find", "search",
        "explore", "review", "clean", "optimize", "merge", "deploy", "push", "pull",
        "revert", "undo", "upgrade", "install", "setup", "migrate", "convert", "extract",
        "split", "combine", "integrate", "connect", "disconnect", "handle", "support",
        "allow", "prevent", "show", "hide", "toggle", "resize", "format", "sort", "filter",
        "validate", "parse", "serialize", "decode", "encode", "fetch", "send", "upload",
        "download", "run", "start", "stop", "restart", "launch", "open", "close", "log",
        "monitor", "track", "watch", "ask"
    ]

    /// Extract a short topic from the user's message using keyword-based extraction.
    /// Strips filler prefixes, finds the action verb and its object, or falls back
    /// to meaningful-word extraction when no verb is found.
    static func extractTopic(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed

        // Strip leading prompt characters
        var stripped = firstLine
        while let first = stripped.unicodeScalars.first,
              first == "\u{276F}" || first == ">" || first == "$" || first == "%" {
            stripped = String(stripped.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // Strip filler prefixes iteratively
        var didStrip = true
        while didStrip {
            didStrip = false
            let lower = stripped.lowercased()
            for prefix in fillerPrefixes {
                if lower.hasPrefix(prefix) {
                    stripped = String(stripped.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespaces)
                    didStrip = true
                    break
                }
            }
        }

        guard !stripped.isEmpty else { return "" }

        let words = stripped.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return "" }

        // Scan for first action verb
        if let verbIndex = words.firstIndex(where: { actionVerbs.contains($0) }) {
            var collected = [words[verbIndex]]
            for word in words[(verbIndex + 1)...] {
                if collected.count >= 4 { break }
                if !stopWords.contains(word) {
                    collected.append(word)
                }
            }
            return capTopic(collected.joined(separator: " "))
        }

        // No verb found: drop stop words, take first 4 remaining
        let meaningful = words.filter { !stopWords.contains($0) }.prefix(4)
        return capTopic(meaningful.joined(separator: " "))
    }

    /// Cap topic at 30 characters, truncating to last complete word within 27 chars.
    private static func capTopic(_ topic: String) -> String {
        guard topic.count > 30 else { return topic }
        let truncated = String(topic.prefix(27))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }

    /// Read ~/.claude/sessions/*.json to get session IDs of currently running Claude processes.
    private static func activeSessionIDs() -> Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessionsDir = home.appendingPathComponent(".claude/sessions", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        var result = Set<String>()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionId = json["sessionId"] as? String,
                  let pid = json["pid"] as? Int else { continue }

            guard kill(pid_t(pid), 0) == 0 else {
                try? FileManager.default.removeItem(at: file)
                continue
            }

            result.insert(sessionId)
        }
        return result
    }

    struct ScanResult {
        let activity: Activity
        let topics: [String]
    }

    /// Read tail of a JSONL file, classify activity and extract topics.
    static func classifyActivity(fileURL: URL, lastModified: Date, now: Date) -> ScanResult {
        let empty = ScanResult(activity: .sleeping, topics: [])

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

        let lines = content.components(separatedBy: .newlines)
            .suffix(30)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(20)

        var activity: Activity = .sleeping
        var topics: [String] = []

        var sawSessionReset = false

        for line in lines.reversed() {
            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String

            // Detect session-reset events before we classify activity.
            if activity == .sleeping {
                if type == "queue-operation" {
                    sawSessionReset = true
                } else if type == "system" {
                    let content = json["content"] as? String ?? ""
                    if content.contains("compacted") || content.contains("Conversation") {
                        sawSessionReset = true
                    }
                }
            }

            // Extract topics from user messages (collect up to 3, walking backwards)
            if topics.count < 3, type == "user",
               let message = json["message"] as? [String: Any] {
                let msgContent = message["content"] as? String
                    ?? (message["role"] as? String == "user" ? message["content"] as? String : nil)
                if let content = msgContent {
                    let extracted = Self.extractTopic(from: content)
                    if !extracted.isEmpty {
                        topics.append(extracted)
                    }
                }
            }

            // Skip if we already classified activity
            guard activity == .sleeping else { continue }

            // Check for assistant end_turn — distinguish asking vs done.
            if type == "assistant",
               let message = json["message"] as? [String: Any],
               message["stop_reason"] as? String == "end_turn" {
                if sawSessionReset {
                    activity = .sleeping
                    break
                }
                var isAsking = false
                if let blocks = message["content"] as? [[String: Any]] {
                    for block in blocks {
                        if block["type"] as? String == "tool_use",
                           block["name"] as? String == "AskUserQuestion" {
                            isAsking = true
                            break
                        }
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

        return ScanResult(activity: activity, topics: topics.reversed())
    }
}
