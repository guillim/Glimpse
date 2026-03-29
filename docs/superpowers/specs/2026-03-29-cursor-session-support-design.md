# Cursor IDE Agent Session Support

## Goal

Monitor Cursor's AI agent (agentic composer) sessions alongside Claude Code sessions in Glimpse. Cursor sessions appear as the same pixel-art characters with no visual distinction — a session is a session regardless of source.

## Approach

Extend `SessionMonitor` with a new `CursorSessionProvider` class (Approach A). The provider queries Cursor's SQLite database, returns `[SessionMonitor.Session]`, and `SessionMonitor.discoverSessions()` merges both sources.

## Data Source

### Location

```
~/Library/Application Support/Cursor/User/globalStorage/state.vscdb
```

SQLite database (WAL mode). Table: `cursorDiskKV` (key-value, values are JSON blobs).

### Relevant Keys

| Key pattern | Purpose |
|---|---|
| `composerData:<uuid>` | One per composer session — status, timestamps, prompt text, workspace context |
| `bubbleId:<composerId>:<bubbleId>` | Individual turns — tool calls, diffs, terminal results |

### Access

- Open read-only via C `sqlite3` API (`import SQLite3`, ships with macOS)
- Flags: `SQLITE_OPEN_READONLY | SQLITE_OPEN_URI`
- Open and close connection each poll cycle (don't hold locks)

## New File: `CursorSessionProvider.swift`

Single class with one public method:

```swift
final class CursorSessionProvider {
    func discoverSessions(now: Date) -> [SessionMonitor.Session]
}
```

### Session Discovery

1. Query `composerData:%` entries from `cursorDiskKV`
2. Parse JSON, filter to agentic sessions: `isAgentic == true` or `unifiedMode == "agent"`
3. Identify **active** sessions: `status == "none"` with non-empty `generatingBubbleIds`
4. Also include **recently completed** sessions: `status == "completed"` or `"aborted"` within last 5 minutes (mirrors Claude Code behavior where done sessions stay visible)
5. For each active session, fetch latest `bubbleId:<composerId>:%` entries (LIMIT 5, DESC) to classify activity

### Session Fields

| Session field | Source |
|---|---|
| `id` | `"cursor-" + composerUUID` (avoids collision with Claude Code UUIDs) |
| `projectName` | Workspace folder name from workspace mapping (last path component) |
| `activity` | Classified from latest bubble (see Activity Mapping) |
| `topics` | Raw prompt text from `composerData.text`, truncated to 30 chars |
| `lastModified` | `createdAt` timestamp from latest bubble, or composer `createdAt` |
| `idleDuration` | `now - lastModified` |

### Workspace-to-Project Mapping

Read `~/Library/Application Support/Cursor/User/workspaceStorage/*/workspace.json` files. Each contains `{"folder": "file:///Users/.../my-project"}`. Build a lookup from workspace hash to folder name. Cache this mapping and refresh periodically (every 30 seconds).

## Activity Mapping

For the latest bubble(s) in an active session:

| Cursor signal | Glimpse Activity |
|---|---|
| `ask_question` tool with `status == "loading"` | `.asking` |
| `run_terminal_command_v2` with `status == "loading"` + `additionalData.status == "pending"` + `reviewData.status == "Requested"` | `.asking` |
| `generatingBubbleIds` non-empty, latest bubble has no `toolFormerData` | `.thinking` |
| `toolFormerData.name` in `[read_file_v2, list_dir_v2, ripgrep_raw_search, glob_file_search, semantic_search_full]` | `.reading` |
| `toolFormerData.name` in `[edit_file_v2, delete_file]` | `.writing` |
| `toolFormerData.name == "web_search"` or `"web_fetch"` | `.searching` |
| `toolFormerData.name == "run_terminal_command_v2"` (running, not pending approval) | `.running` |
| Terminal command matches test patterns (pytest, jest, cargo test, etc.) | `.testing` |
| Terminal command matches build patterns (npm build, cargo build, etc.) | `.building` |
| Terminal command matches git patterns (git commit, git push, etc.) | `.committing` |
| `toolFormerData.name == "create_plan"` | `.thinking` |
| `toolFormerData.name == "task_v2"` or `"todo_write"` | `.thinking` |
| `status == "completed"` or `"aborted"` | `.done` |
| No active or recent sessions | `.sleeping` |

### Terminal Command Sub-Classification

When `toolFormerData.name == "run_terminal_command_v2"` and the command is running (not pending approval), extract the command string from `toolFormerData.params` or `rawArgs` and reuse `SessionMonitor.classifyBashCommand`'s pattern matching (git/test/build patterns). This requires making those pattern lists accessible to `CursorSessionProvider` — either make them `static` on `SessionMonitor` (they already are) or extract to a shared utility.

## Integration into SessionMonitor

### Changes to `SessionMonitor.swift`

1. Add property: `private let cursorProvider = CursorSessionProvider()`
2. In `discoverSessions()`, after building Claude Code sessions, append `cursorProvider.discoverSessions(now: now)`
3. The `cursor-` prefix on IDs keeps `scanCache` entries separate — no collisions
4. Cursor sessions flow through the existing `onUpdate` callback unchanged

### No Changes Required

- `CharacterGenerator.swift` — `cursor-` prefixed IDs produce unique deterministic characters
- `CharacterNode.swift` — displays Session data as-is
- `AgentMonitorScene.swift` — grid layout handles any number of sessions
- `DesktopWindowController.swift` — no changes
- `AppDelegate.swift` — no changes

## Cursor Tool ID Reference

For implementation reference:

| ID | Tool Name | Maps to |
|---|---|---|
| 9 | `semantic_search_full` | `.reading` |
| 11 | `delete_file` | `.writing` |
| 15 | `run_terminal_command_v2` | `.running` / `.testing` / `.building` / `.committing` / `.asking` |
| 18 | `web_search` | `.searching` |
| 19 | `mcp--*` | `.running` |
| 38 | `edit_file_v2` | `.writing` |
| 39 | `list_dir_v2` | `.reading` |
| 40 | `read_file_v2` | `.reading` |
| 41 | `ripgrep_raw_search` | `.reading` |
| 42 | `glob_file_search` | `.reading` |
| 43 | `create_plan` | `.thinking` |
| 48 | `task_v2` | `.thinking` |
| 51 | `ask_question` | `.asking` |
| 56 | `record_screen` | `.running` |
| 57 | `web_fetch` | `.searching` |

## Edge Cases

- **Cursor not installed**: `CursorSessionProvider` returns `[]` if the database doesn't exist. No error.
- **Database locked**: If SQLite open fails (Cursor updating the DB), return `[]` for that cycle. Next poll retries.
- **Schema changes**: If expected keys/fields are missing, skip that session gracefully. Log nothing (background app).
- **Stale sessions**: Sessions with `status == "completed"` older than 5 minutes are excluded.
- **Click-to-activate**: Clicking a Cursor session character should activate the Cursor app window. Use `NSWorkspace.shared.open` to bring Cursor to front (simpler than the TTY-matching approach used for terminal apps).
