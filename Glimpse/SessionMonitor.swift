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
        let projectName: String   // Extracted from parent directory name
        let activity: Activity
        let lastModified: Date
        /// True if modified 5–10 minutes ago (stale tier). PokemonScene uses this to trigger goodbye/fade-out animation.
        let isStale: Bool

        static func == (lhs: Session, rhs: Session) -> Bool {
            lhs.id == rhs.id && lhs.activity == rhs.activity
        }
    }

    /// Called on the main thread when sessions change.
    var onUpdate: (([Session]) -> Void)?

    private var timer: Timer?
    private var previousSessions: [String: Session] = [:]

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
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let sessions = self.discoverSessions()
            DispatchQueue.main.async {
                self.previousSessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
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
        ) else { return [] }

        var sessions: [Session] = []
        let now = Date()
        let activeThreshold: TimeInterval = 5 * 60    // 5 minutes  → active tier
        let staleThreshold: TimeInterval  = 10 * 60   // 10 minutes → stale tier (dead beyond this)

        for dirURL in projectDirs {
            guard (try? dirURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

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
            ) else { continue }

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
                let activity = Self.classifyActivity(fileURL: fileURL, lastModified: modified, now: now)

                sessions.append(Session(
                    id: sessionID,
                    projectName: projectName,
                    activity: activity,
                    lastModified: modified,
                    isStale: isStale
                ))
            }
        }

        return sessions
    }

    /// Extract human-readable project name from encoded directory name.
    /// "-Users-gui-github-background" → "background"
    static func extractProjectName(from dirName: String) -> String {
        let components = dirName.split(separator: "-").map(String.init)
        return components.last ?? dirName
    }

    /// Read last ~10 lines of a JSONL file and classify activity.
    static func classifyActivity(fileURL: URL, lastModified: Date, now: Date) -> Activity {
        // If no activity for 2+ minutes, sleeping
        if now.timeIntervalSince(lastModified) > 120 { return .sleeping }

        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return .sleeping
        }

        // Get last ~10 non-empty lines
        let lines = content.components(separatedBy: .newlines)
            .suffix(15)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(10)

        // Walk backwards to find the most recent meaningful message
        for line in lines.reversed() {
            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String

            // Check for assistant message with tool use (reading)
            if type == "assistant",
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {

                // Check for tool_use blocks — reading tools
                let readingTools: Set<String> = ["Read", "Glob", "Grep"]
                for block in content {
                    if block["type"] as? String == "tool_use",
                       let toolName = block["name"] as? String,
                       readingTools.contains(toolName) {
                        return .reading
                    }
                }

                // Check for text output — talking
                for block in content {
                    if block["type"] as? String == "text" {
                        return .talking
                    }
                }
            }

            // Check for assistant end_turn — waiting for human
            if type == "assistant",
               let message = json["message"] as? [String: Any],
               message["stop_reason"] as? String == "end_turn" {
                // If last modified > 30s ago, waiting for input
                if now.timeIntervalSince(lastModified) > 30 {
                    return .waiting
                }
                return .talking  // just finished talking
            }

            // User message — session is active, agent is probably processing
            if type == "user" {
                return .talking
            }
        }

        return .sleeping
    }
}
