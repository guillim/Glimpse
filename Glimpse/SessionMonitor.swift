// Glimpse/SessionMonitor.swift
import Foundation

/// Monitors active Claude Code sessions by scanning ~/.claude/ JSONL log files.
/// Polls every 5 seconds and notifies a delegate of session changes.
final class SessionMonitor {

    /// Activity state for a single Claude Code session.
    enum Activity: Equatable {
        case reading    // Agent is reading files (Read, Glob, Grep tools)
        case talking    // Agent is outputting a text response
        case waiting    // Session waiting for human input
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
        /// True if modified 60s–2min ago (stale tier). PokemonScene uses this to trigger goodbye/fade-out animation.
        let isStale: Bool

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

    /// Base directory for Claude Code projects.
    private let claudeProjectsDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/projects", isDirectory: true)
    }()

    /// Start polling every 5 seconds.
    func start() {
        stop()
        // Fire immediately, then every 5s.
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    /// Stop polling.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One scan cycle: discover sessions, classify activity, notify delegate.
    private func scan() {
        // Run synchronously on main thread for reliability.
        // File I/O is fast enough for ~10 project dirs with tail-reads.
        let sessions = discoverSessions()
        onUpdate?(sessions)
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
        let activeThreshold: TimeInterval = 60     // 60 seconds → active tier
        let staleThreshold: TimeInterval  = 120    // 2 minutes  → stale tier (dead beyond this)

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

                // Dead sessions (10+ minutes old) are ignored entirely.
                guard age < staleThreshold else { continue }

                // Active: < 5 min.  Stale: 5–10 min (PokemonScene triggers goodbye animation).
                let isStale = age >= activeThreshold

                let sessionID = fileURL.deletingPathExtension().lastPathComponent
                let result = Self.classifyActivityAndTopic(fileURL: fileURL, lastModified: modified, now: now)

                sessions.append(Session(
                    id: sessionID,
                    projectName: projectName,
                    projectDirName: dirURL.lastPathComponent,
                    activity: result.activity,
                    topic: result.topic,
                    lastOutput: result.lastOutput,
                    lastModified: modified,
                    isStale: isStale
                ))
            }
        }

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

    struct ScanResult {
        let activity: Activity
        let topic: String
        let lastOutput: String
    }

    /// Read last ~20 lines of a JSONL file, classify activity, extract topic, and last output.
    /// Uses FileHandle to read only the tail of potentially large files.
    static func classifyActivityAndTopic(fileURL: URL, lastModified: Date, now: Date) -> ScanResult {
        let empty = ScanResult(activity: .sleeping, topic: "", lastOutput: "")
        // If no activity for 2+ minutes, sleeping
        if now.timeIntervalSince(lastModified) > 120 { return empty }

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

            // Check for assistant message with tool use (reading)
            if type == "assistant",
               let message = json["message"] as? [String: Any],
               let blocks = message["content"] as? [[String: Any]] {

                let readingTools: Set<String> = ["Read", "Glob", "Grep"]
                for block in blocks {
                    if block["type"] as? String == "tool_use",
                       let toolName = block["name"] as? String,
                       readingTools.contains(toolName) {
                        activity = .reading
                    }
                }

                if activity == .sleeping {
                    for block in blocks {
                        if block["type"] as? String == "text" {
                            activity = .talking
                        }
                    }
                }
            }

            // Check for assistant end_turn — waiting for human
            if activity == .sleeping, type == "assistant",
               let message = json["message"] as? [String: Any],
               message["stop_reason"] as? String == "end_turn" {
                activity = now.timeIntervalSince(lastModified) > 30 ? .waiting : .talking
            }

            // User message — session is active, agent is probably processing
            if activity == .sleeping, type == "user" {
                activity = .talking
            }
        }

        return ScanResult(activity: activity, topic: topic, lastOutput: lastOutput)
    }
}
