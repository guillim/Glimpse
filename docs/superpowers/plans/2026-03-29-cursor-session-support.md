# Cursor IDE Agent Session Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Monitor Cursor's agentic composer sessions alongside Claude Code sessions in Glimpse, with full activity detection including asking state.

**Architecture:** New `CursorSessionProvider` class queries Cursor's SQLite database (`state.vscdb`) and returns `[SessionMonitor.Session]`. `SessionMonitor.discoverSessions()` merges results from both sources. All downstream rendering code works unchanged.

**Tech Stack:** Swift, SQLite3 C API (ships with macOS), existing Glimpse architecture

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `Glimpse/CursorSessionProvider.swift` | Create | SQLite queries, JSON parsing, activity classification for Cursor sessions |
| `Glimpse/SessionMonitor.swift` | Modify | Add `classifyTerminalCommand(_:)` static method, integrate CursorSessionProvider |
| `Glimpse/AgentMonitorScene.swift` | Modify | Add Cursor click-to-activate handling |

---

### Task 1: Extract shared terminal command classifier from SessionMonitor

The existing `classifyBashCommand(blocks:)` works on Claude Code's JSON block structure. Cursor needs to classify raw command strings. Extract a reusable static method.

**Files:**
- Modify: `Glimpse/SessionMonitor.swift:551-587`

- [ ] **Step 1: Add `classifyTerminalCommand(_:)` static method**

Add this method right before the existing `classifyBashCommand` method (line 551):

```swift
/// Classify a raw terminal command string into an activity.
/// Shared by Claude Code and Cursor session providers.
static func classifyTerminalCommand(_ command: String) -> Activity {
    let cmd = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

    for pattern in gitPatterns {
        if cmd.hasPrefix(pattern) || cmd.contains("&& \(pattern)") || cmd.contains("; \(pattern)") {
            return .committing
        }
    }
    for pattern in testPatterns {
        if cmd.hasPrefix(pattern) || cmd.contains("&& \(pattern)") || cmd.contains("; \(pattern)") {
            return .testing
        }
    }
    for pattern in buildPatterns {
        if cmd.hasPrefix(pattern) || cmd.contains("&& \(pattern)") || cmd.contains("; \(pattern)") {
            return .building
        }
    }
    return .running
}
```

- [ ] **Step 2: Refactor `classifyBashCommand` to use the new method**

Replace the body of `classifyBashCommand(blocks:)` to delegate to the new method:

```swift
private static func classifyBashCommand(blocks: [[String: Any]]) -> Activity {
    for block in blocks.reversed() {
        guard block["type"] as? String == "tool_use",
              block["name"] as? String == "Bash",
              let input = block["input"] as? [String: Any],
              let command = input["command"] as? String else { continue }
        return classifyTerminalCommand(command)
    }
    return .running
}
```

- [ ] **Step 3: Build to verify no regressions**

Run:
```bash
cd /Users/guillaumelancrenon/github/background && xcodebuild -scheme Glimpse -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Glimpse/SessionMonitor.swift
git commit -m "refactor: extract classifyTerminalCommand for shared use"
```

---

### Task 2: Create CursorSessionProvider — SQLite access and session discovery

**Files:**
- Create: `Glimpse/CursorSessionProvider.swift`

- [ ] **Step 1: Create the file with SQLite access and composer query**

Create `Glimpse/CursorSessionProvider.swift`:

```swift
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
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
cd /Users/guillaumelancrenon/github/background && xcodebuild -scheme Glimpse -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Glimpse/CursorSessionProvider.swift
git commit -m "feat: add CursorSessionProvider for Cursor agent session discovery"
```

---

### Task 3: Integrate CursorSessionProvider into SessionMonitor

**Files:**
- Modify: `Glimpse/SessionMonitor.swift:6` (add property)
- Modify: `Glimpse/SessionMonitor.swift:88-160` (merge in discoverSessions)

- [ ] **Step 1: Add CursorSessionProvider property**

In `SessionMonitor`, after the `scanQueue` property (line 50), add:

```swift
/// Provider for Cursor IDE agent sessions.
private let cursorProvider = CursorSessionProvider()
```

- [ ] **Step 2: Merge Cursor sessions into discoverSessions()**

In `discoverSessions()`, right before the `// Prune cache entries` comment (line 155), add:

```swift
// Merge Cursor agent sessions
let cursorSessions = cursorProvider.discoverSessions(now: now)
sessions.append(contentsOf: cursorSessions)
```

- [ ] **Step 3: Build to verify integration compiles**

Run:
```bash
cd /Users/guillaumelancrenon/github/background && xcodebuild -scheme Glimpse -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Glimpse/SessionMonitor.swift
git commit -m "feat: integrate Cursor sessions into SessionMonitor discovery"
```

---

### Task 4: Add click-to-activate for Cursor sessions

When a user clicks a Cursor session character, bring Cursor to the foreground.

**Files:**
- Modify: `Glimpse/AgentMonitorScene.swift:134-153`

- [ ] **Step 1: Update `activateAppForSession` to handle Cursor sessions**

Replace the `activateAppForSession` method with:

```swift
/// Resolve a session ID to its parent GUI app and activate it.
func activateAppForSession(_ sessionID: String) {
    // Cursor sessions: just bring Cursor to front
    if sessionID.hasPrefix("cursor-") {
        DispatchQueue.global(qos: .userInitiated).async {
            let workspace = NSWorkspace.shared
            if let cursorURL = workspace.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
                DispatchQueue.main.async {
                    workspace.openApplication(at: cursorURL, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
        return
    }

    // Claude Code sessions: find parent terminal and activate
    DispatchQueue.global(qos: .userInitiated).async {
        guard let pid = Self.findSessionPID(sessionID) else { return }
        guard let app = Self.findParentGUIApp(pid: pid) else { return }

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
```

- [ ] **Step 2: Build to verify**

Run:
```bash
cd /Users/guillaumelancrenon/github/background && xcodebuild -scheme Glimpse -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Glimpse/AgentMonitorScene.swift
git commit -m "feat: click-to-activate for Cursor sessions"
```

---

### Task 5: Manual integration test

**Files:** None (testing only)

- [ ] **Step 1: Build and run**

Run:
```bash
cd /Users/guillaumelancrenon/github/background && xcodebuild -scheme Glimpse -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Launch Glimpse and verify**

Open the built app. Verify:
1. Existing Claude Code sessions still appear correctly (no regressions)
2. If Cursor is open with an active agent session, it appears as a character
3. The character has a unique procedural appearance (from `cursor-<uuid>` ID)
4. Activity state updates as the Cursor agent works
5. When the agent asks a question or requests terminal approval, state shows as "ASKING" with orange glow
6. Clicking the Cursor character brings Cursor to front
7. If Cursor is not installed, no errors — just no Cursor sessions shown

- [ ] **Step 3: Update empty-state label**

The current empty-state label says "No Claude sessions active". Now that we support Cursor too, update it in `AgentMonitorScene.swift`. Find the `emptyLabel` declaration and change the text:

In `Glimpse/AgentMonitorScene.swift`, replace:
```swift
label.text = "No Claude sessions active — start one to see your agent!"
```
with:
```swift
label.text = "No agent sessions active — start one to see your agent!"
```

- [ ] **Step 4: Build and verify the label change**

Run:
```bash
cd /Users/guillaumelancrenon/github/background && xcodebuild -scheme Glimpse -configuration Debug build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Glimpse/AgentMonitorScene.swift
git commit -m "chore: update empty-state label for multi-source support"
```

---

### Task 6: Update TODO.md

**Files:**
- Modify: `TODO.md`

- [ ] **Step 1: Mark Cursor session support as done**

In `TODO.md`, replace:
```markdown
- [ ] **Cursor IDE session support** — Monitor Cursor sessions in addition to Claude Code. Requires discovering Cursor's log format and storage location.
```
with:
```markdown
- [x] **Cursor IDE session support** — Monitor Cursor agent sessions via state.vscdb SQLite database. *(Implemented)*
```

- [ ] **Step 2: Commit**

```bash
git add TODO.md
git commit -m "docs: mark Cursor session support as complete"
```
