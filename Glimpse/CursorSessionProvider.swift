// Glimpse/CursorSessionProvider.swift
import Foundation
import SQLite3

/// Discovers active Cursor AI agent sessions by querying Cursor's state.vscdb SQLite database.
final class CursorSessionProvider {

    /// Path to Cursor's global state database.
    private let dbPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }()

    /// Cached workspace hash → project folder name mapping.
    private var workspaceMap: [String: String] = [:]
    private var workspaceMapLastRefresh: Date = .distantPast

    /// Discover active Cursor agent sessions.
    func discoverSessions(now: Date) -> [SessionMonitor.Session] {
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        // Refresh workspace map every 30 seconds
        if now.timeIntervalSince(workspaceMapLastRefresh) > 30 {
            workspaceMap = Self.buildWorkspaceMap()
            workspaceMapLastRefresh = now
        }

        let composers = queryComposerData(db: db!)
        var sessions: [SessionMonitor.Session] = []

        for composer in composers {
            let isAgent = composer.isAgentic || composer.unifiedMode == "agent"
            guard isAgent else { continue }

            let isActive = composer.status == "none" && !composer.generatingBubbleIds.isEmpty
            let isRecent: Bool
            if composer.status == "completed" || composer.status == "aborted" {
                isRecent = now.timeIntervalSince(composer.lastModified) < 300 // 5 minutes
            } else {
                isRecent = false
            }

            guard isActive || isRecent else { continue }

            let activity: SessionMonitor.Activity
            if isActive {
                activity = classifyActivity(db: db!, composerId: composer.id)
            } else {
                activity = .done
            }

            let topic = Self.truncateTopic(composer.text, maxLength: 30)

            sessions.append(SessionMonitor.Session(
                id: "cursor-\(composer.id)",
                projectName: composer.projectName,
                activity: activity,
                topics: topic.isEmpty ? [] : [topic],
                lastModified: composer.lastModified,
                idleDuration: now.timeIntervalSince(composer.lastModified)
            ))
        }

        return sessions
    }

    // MARK: - Composer Data

    private struct ComposerData {
        let id: String
        let status: String
        let isAgentic: Bool
        let unifiedMode: String
        let generatingBubbleIds: [String]
        let text: String
        let projectName: String
        let lastModified: Date
    }

    private func queryComposerData(db: OpaquePointer) -> [ComposerData] {
        let sql = "SELECT key, value FROM cursorDiskKV WHERE key LIKE 'composerData:%'"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [ComposerData] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let keyPtr = sqlite3_column_text(stmt, 0),
                  let valPtr = sqlite3_column_text(stmt, 1) else { continue }

            let key = String(cString: keyPtr)
            let composerId = String(key.dropFirst("composerData:".count))

            guard let data = String(cString: valPtr).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let status = json["status"] as? String ?? "none"
            let isAgentic = json["isAgentic"] as? Bool ?? false
            let unifiedMode = json["unifiedMode"] as? String ?? ""
            let generatingBubbleIds = json["generatingBubbleIds"] as? [String] ?? []
            let text = json["text"] as? String ?? ""

            // Extract project name from context or workspace mapping
            let projectName = extractProjectName(from: json)

            // Parse timestamp
            let createdAt = json["createdAt"] as? Double ?? 0
            let lastModified = createdAt > 0
                ? Date(timeIntervalSince1970: createdAt / 1000) // milliseconds
                : Date.distantPast

            results.append(ComposerData(
                id: composerId,
                status: status,
                isAgentic: isAgentic,
                unifiedMode: unifiedMode,
                generatingBubbleIds: generatingBubbleIds,
                text: text,
                projectName: projectName,
                lastModified: lastModified
            ))
        }

        return results
    }

    // MARK: - Activity Classification

    /// Classify the activity of an active Cursor session by reading its latest bubbles.
    private func classifyActivity(db: OpaquePointer, composerId: String) -> SessionMonitor.Activity {
        let sql = "SELECT value FROM cursorDiskKV WHERE key LIKE ?1 ORDER BY key DESC LIMIT 5"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return .thinking }
        let pattern = "bubbleId:\(composerId):%"
        sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let valPtr = sqlite3_column_text(stmt, 0),
                  let data = String(cString: valPtr).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            // Only classify from AI response bubbles (type 2)
            let bubbleType = json["type"] as? Int ?? 0
            guard bubbleType == 2 else { continue }

            guard let toolData = json["toolFormerData"] as? [String: Any] else {
                // No tool call — agent is generating text
                return .thinking
            }

            let toolName = toolData["name"] as? String ?? ""
            let toolStatus = toolData["status"] as? String ?? ""

            // Check for asking states first
            if toolName == "ask_question" && toolStatus == "loading" {
                return .asking
            }

            if toolName == "run_terminal_command_v2" {
                if let additionalData = toolData["additionalData"] as? [String: Any],
                   additionalData["status"] as? String == "pending",
                   let reviewData = additionalData["reviewData"] as? [String: Any],
                   reviewData["status"] as? String == "Requested" {
                    return .asking
                }

                // Running terminal command — sub-classify
                if let params = toolData["params"] as? String,
                   let paramsData = params.data(using: .utf8),
                   let paramsJson = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any],
                   let command = paramsJson["command"] as? String {
                    return SessionMonitor.classifyTerminalCommand(command)
                }
                if let rawArgs = toolData["rawArgs"] as? String {
                    return SessionMonitor.classifyTerminalCommand(rawArgs)
                }
                return .running
            }

            // Reading tools
            let readingTools: Set<String> = [
                "read_file_v2", "list_dir_v2", "ripgrep_raw_search",
                "glob_file_search", "semantic_search_full"
            ]
            if readingTools.contains(toolName) { return .reading }

            // Writing tools
            let writingTools: Set<String> = ["edit_file_v2", "delete_file"]
            if writingTools.contains(toolName) { return .writing }

            // Searching tools
            let searchingTools: Set<String> = ["web_search", "web_fetch"]
            if searchingTools.contains(toolName) { return .searching }

            // Planning/thinking tools
            let thinkingTools: Set<String> = ["create_plan", "task_v2", "todo_write"]
            if thinkingTools.contains(toolName) { return .thinking }

            // MCP or other tools
            return .running
        }

        // No bubbles found — generating
        return .thinking
    }

    // MARK: - Project Name

    /// Extract project name from composer context or workspace mapping.
    private func extractProjectName(from json: [String: Any]) -> String {
        // Try to get workspace folder from context
        if let context = json["context"] as? [String: Any],
           let folders = context["folders"] as? [[String: Any]],
           let first = folders.first,
           let path = first["path"] as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        // Try workspace URI from context
        if let context = json["context"] as? [String: Any],
           let uri = context["workspaceFolder"] as? String,
           let url = URL(string: uri) {
            return url.lastPathComponent
        }

        // Fall back to workspace map lookup via workspaceId
        if let wsId = json["workspaceId"] as? String,
           let name = workspaceMap[wsId] {
            return name
        }

        return "Cursor"
    }

    // MARK: - Workspace Mapping

    /// Build a mapping from workspace storage hashes to project folder names.
    static func buildWorkspaceMap() -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let storageDir = home.appendingPathComponent(
            "Library/Application Support/Cursor/User/workspaceStorage",
            isDirectory: true
        )
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: storageDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [:] }

        var map: [String: String] = [:]
        for dir in dirs {
            let wsFile = dir.appendingPathComponent("workspace.json")
            guard let data = try? Data(contentsOf: wsFile),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let folder = json["folder"] as? String,
                  let url = URL(string: folder) else { continue }
            map[dir.lastPathComponent] = url.lastPathComponent
        }
        return map
    }

    // MARK: - Topic Truncation

    /// Truncate raw prompt text to maxLength, breaking at last word boundary.
    static func truncateTopic(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard trimmed.count > maxLength else { return trimmed }

        let truncated = String(trimmed.prefix(maxLength - 3))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }
}
