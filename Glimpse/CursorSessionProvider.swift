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

    /// Cached composerId → project folder name mapping (built from per-workspace DBs).
    private var composerProjectMap: [String: String] = [:]
    private var composerProjectMapLastRefresh: Date = .distantPast

    /// Discover active Cursor agent sessions.
    func discoverSessions(now: Date) -> [SessionMonitor.Session] {
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        // Refresh composer→project map every 30 seconds
        if now.timeIntervalSince(composerProjectMapLastRefresh) > 30 {
            composerProjectMap = Self.buildComposerProjectMap()
            composerProjectMapLastRefresh = now
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
            let effectiveLastModified: Date
            let lastAssistantText: String?
            if isActive {
                let classification = classifyActivity(db: db!, composerId: composer.id)
                activity = classification.activity
                lastAssistantText = classification.lastAssistantText
                effectiveLastModified = latestBubbleDate(db: db!, composerId: composer.id) ?? composer.lastModified
            } else {
                activity = .done
                lastAssistantText = nil
                effectiveLastModified = composer.lastModified
            }

            // Prefer AI-generated name, fall back to user text
            let topicSource = composer.name.isEmpty ? composer.text : composer.name
            let topic = Self.truncateTopic(topicSource, maxLength: 30)

            sessions.append(SessionMonitor.Session(
                id: "cursor-\(composer.id)",
                projectName: composer.projectName,
                activity: activity,
                topics: topic.isEmpty ? [] : [topic],
                summary: topic,
                lastModified: effectiveLastModified,
                idleDuration: now.timeIntervalSince(effectiveLastModified),
                lastAssistantText: lastAssistantText
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
        let name: String
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
            let name = json["name"] as? String ?? ""

            // Extract project name from context, workspace mapping, or file URIs
            let projectName = extractProjectName(composerId: composerId, from: json)

            // Parse timestamps — prefer lastUpdatedAt, fall back to createdAt
            let lastUpdatedAt = json["lastUpdatedAt"] as? Double ?? 0
            let createdAt = json["createdAt"] as? Double ?? 0
            let bestEpoch = lastUpdatedAt > 0 ? lastUpdatedAt : createdAt
            let lastModified = bestEpoch > 0
                ? Date(timeIntervalSince1970: bestEpoch / 1000) // milliseconds
                : Date.distantPast

            results.append(ComposerData(
                id: composerId,
                status: status,
                isAgentic: isAgentic,
                unifiedMode: unifiedMode,
                generatingBubbleIds: generatingBubbleIds,
                text: text,
                name: name,
                projectName: projectName,
                lastModified: lastModified
            ))
        }

        return results
    }

    /// Query the latest bubble timestamp for a composer (ISO 8601 → Date).
    private func latestBubbleDate(db: OpaquePointer, composerId: String) -> Date? {
        let sql = """
            SELECT json_extract(value, '$.createdAt') FROM cursorDiskKV
            WHERE key LIKE ?1
            ORDER BY json_extract(value, '$.createdAt') DESC LIMIT 1
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        let pattern = "bubbleId:\(composerId):%"
        _ = pattern.withCString { cStr in
            sqlite3_bind_text(stmt, 1, cStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let ptr = sqlite3_column_text(stmt, 0) else { return nil }
        let iso = String(cString: ptr)
        return Self.isoFormatter.date(from: iso)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Activity Classification

    private static let readingTools: Set<String> = [
        "read_file_v2", "list_dir_v2", "ripgrep_raw_search",
        "glob_file_search", "semantic_search_full"
    ]
    private static let writingTools: Set<String> = ["edit_file_v2", "delete_file"]
    private static let searchingTools: Set<String> = ["web_search", "web_fetch"]
    private static let thinkingTools: Set<String> = ["create_plan", "task_v2", "todo_write"]

    /// Classify the activity of an active Cursor session by reading its latest bubbles.
    /// Returns the activity and optional question text when asking.
    private func classifyActivity(db: OpaquePointer, composerId: String) -> (activity: SessionMonitor.Activity, lastAssistantText: String?) {
        let sql = "SELECT value FROM cursorDiskKV WHERE key LIKE ?1 ORDER BY json_extract(value, '$.createdAt') DESC LIMIT 5"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return (.thinking, nil) }
        let pattern = "bubbleId:\(composerId):%"
        _ = pattern.withCString { cStr in
            sqlite3_bind_text(stmt, 1, cStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
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
                return (.thinking, nil)
            }

            let toolName = toolData["name"] as? String ?? ""
            let toolStatus = toolData["status"] as? String ?? ""

            // Check for asking states first
            if toolName == "ask_question" && toolStatus == "loading" {
                // Extract question text from params
                var lastAssistantText: String?
                if let params = toolData["params"] as? String,
                   let paramsData = params.data(using: .utf8),
                   let paramsJson = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any],
                   let q = paramsJson["question"] as? String {
                    lastAssistantText = q
                }
                return (.asking, lastAssistantText)
            }

            if toolName == "run_terminal_command_v2" {
                if let additionalData = toolData["additionalData"] as? [String: Any],
                   additionalData["status"] as? String == "pending",
                   let reviewData = additionalData["reviewData"] as? [String: Any],
                   reviewData["status"] as? String == "Requested" {
                    return (.asking, nil)
                }

                // Running terminal command — sub-classify
                if let params = toolData["params"] as? String,
                   let paramsData = params.data(using: .utf8),
                   let paramsJson = try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any],
                   let command = paramsJson["command"] as? String {
                    return (SessionMonitor.classifyTerminalCommand(command), nil)
                }
                if let rawArgs = toolData["rawArgs"] as? String {
                    return (SessionMonitor.classifyTerminalCommand(rawArgs), nil)
                }
                return (.running, nil)
            }

            if Self.readingTools.contains(toolName) { return (.reading, nil) }
            if Self.writingTools.contains(toolName) { return (.writing, nil) }
            if Self.searchingTools.contains(toolName) { return (.searching, nil) }
            if Self.thinkingTools.contains(toolName) { return (.thinking, nil) }

            // MCP or other tools
            return (.running, nil)
        }

        // No bubbles found — generating
        return (.thinking, nil)
    }

    // MARK: - Project Name

    /// Extract project name from composer context or workspace mapping.
    private func extractProjectName(composerId: String, from json: [String: Any]) -> String {
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

        // Look up composer→project mapping from per-workspace DBs
        if let name = composerProjectMap[composerId] {
            return name
        }

        // Infer project name from file URIs in context mentions or changed files
        if let name = inferProjectNameFromFileURIs(json: json) {
            return name
        }

        return "Cursor"
    }

    /// Infer project folder name from file URIs found in composer data.
    private func inferProjectNameFromFileURIs(json: [String: Any]) -> String? {
        // Collect file URIs from various sources
        var fileURIs: [String] = []

        // From context mentions (fileSelections keys are URIs)
        if let context = json["context"] as? [String: Any],
           let mentions = context["mentions"] as? [String: Any],
           let fileSelections = mentions["fileSelections"] as? [String: Any] {
            for key in fileSelections.keys {
                if key.hasPrefix("file://") {
                    fileURIs.append(key)
                }
            }
        }

        // From newlyCreatedFiles (array of objects with uri.path)
        if let created = json["newlyCreatedFiles"] as? [[String: Any]] {
            for entry in created {
                if let uri = entry["uri"] as? [String: Any],
                   let path = uri["path"] as? String {
                    fileURIs.append(path)
                } else if let uri = entry["uri"] as? [String: Any],
                          let external = uri["external"] as? String {
                    fileURIs.append(external)
                }
            }
        }

        // From addedFiles (may be an array of objects or an int in newer Cursor versions)
        if let added = json["addedFiles"] as? [[String: Any]] {
            for entry in added {
                if let uri = entry["uri"] as? [String: Any],
                   let path = uri["path"] as? String {
                    fileURIs.append(path)
                }
            }
        }

        // From allAttachedFileCodeChunksUris
        if let attached = json["allAttachedFileCodeChunksUris"] as? [String] {
            fileURIs.append(contentsOf: attached)
        }

        // From originalFileStates (keys are file URIs)
        if let originals = json["originalFileStates"] as? [String: Any] {
            for key in originals.keys {
                if key.hasPrefix("file://") {
                    fileURIs.append(key)
                }
            }
        }

        // Normalize URIs to paths
        var paths: [String] = []
        for uri in fileURIs {
            if uri.hasPrefix("file://"), let url = URL(string: uri) {
                paths.append(url.path)
            } else if uri.hasPrefix("/") {
                paths.append(uri)
            }
        }

        guard !paths.isEmpty else { return nil }

        // Use directory components only (strip filename from each path)
        var dirComponents: [[String]] = paths.map { path in
            var comps = path.split(separator: "/").map(String.init)
            // Remove the last component if it looks like a file (has an extension)
            if let last = comps.last, last.contains(".") {
                comps.removeLast()
            }
            return comps
        }

        // Find the longest common directory prefix across all paths
        guard var commonComponents = dirComponents.first else { return nil }
        for comps in dirComponents.dropFirst() {
            let minLen = min(commonComponents.count, comps.count)
            var matchLen = 0
            for i in 0..<minLen {
                if commonComponents[i] == comps[i] {
                    matchLen = i + 1
                } else {
                    break
                }
            }
            commonComponents = Array(commonComponents.prefix(matchLen))
        }

        // The common prefix is the project root (or deeper).
        // Return its last component as the project name.
        if let last = commonComponents.last, !last.isEmpty {
            return last
        }

        return nil
    }

    // MARK: - Workspace Mapping

    /// Build a mapping from composerId → project folder name by scanning per-workspace DBs.
    /// Each workspace storage directory has a `workspace.json` (with the folder URI) and a
    /// `state.vscdb` whose `ItemTable` key `composer.composerData` lists all composer IDs
    /// that belong to that workspace.
    static func buildComposerProjectMap() -> [String: String] {
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
            // Read workspace folder URI
            let wsFile = dir.appendingPathComponent("workspace.json")
            guard let wsData = try? Data(contentsOf: wsFile),
                  let wsJson = try? JSONSerialization.jsonObject(with: wsData) as? [String: Any],
                  let folder = wsJson["folder"] as? String,
                  let url = URL(string: folder) else { continue }
            let projectName = url.lastPathComponent

            // Read composer IDs from per-workspace state DB
            let dbPath = dir.appendingPathComponent("state.vscdb").path
            guard FileManager.default.fileExists(atPath: dbPath) else { continue }

            var db: OpaquePointer?
            let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
            let uri = "file:\(dbPath)?immutable=1"
            guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK else { continue }
            defer { sqlite3_close(db) }

            let sql = "SELECT value FROM ItemTable WHERE key = 'composer.composerData'"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_step(stmt) == SQLITE_ROW,
                  let valPtr = sqlite3_column_text(stmt, 0),
                  let data = String(cString: valPtr).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let allComposers = json["allComposers"] as? [[String: Any]] else { continue }

            for composer in allComposers {
                if let composerId = composer["composerId"] as? String {
                    map[composerId] = projectName
                }
            }
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
