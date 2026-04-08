// Glimpse/SessionMonitor.swift
import Foundation
import NaturalLanguage

/// Monitors active Claude Code sessions by scanning ~/.claude/ JSONL log files.
/// Polls every 2 seconds and notifies via callback on session changes.
final class SessionMonitor {

    /// Activity state for a single Claude Code session.
    enum Activity: Equatable {
        case reading     // Agent is reading files (Read, Glob, Grep tools)
        case writing     // Agent is editing/creating files (Edit, Write tools)
        case running     // Agent is running shell commands (Bash tool — generic)
        case testing     // Agent is running tests (Bash: test/spec/jest/pytest etc.)
        case building    // Agent is compiling/building (Bash: build/make/tsc etc.)
        case committing  // Agent is doing git operations (Bash: git commit/push/add etc.)
        case thinking    // Agent is reasoning/planning (text output, no tool_use)
        case processing  // User sent a message, agent hasn't responded yet
        case spawning    // Agent is launching subagents (Agent tool)
        case searching   // Agent is searching the web (WebSearch, WebFetch tools)
        case asking      // Agent asked the user a question (end_turn with question mark or AskUserQuestion)
        case done        // Agent finished its task (end_turn, no question)
        case sleeping    // Active but idle
    }

    /// Snapshot of a discovered session.
    struct Session: Equatable {
        let id: String            // JSONL filename (UUID)
        let projectName: String   // Extracted from parent directory name
        let activity: Activity
        let topics: [String]      // Last up-to-3 user input topics (oldest first)
        let summary: String       // NLTagger keyword summary of most recent user input
        let lastModified: Date
        /// How long (in seconds) the session has been idle (0 when actively producing output).
        let idleDuration: TimeInterval
        /// The question text when activity is .asking (nil otherwise).
        let lastAssistantText: String?

        static func == (lhs: Session, rhs: Session) -> Bool {
            lhs.id == rhs.id && lhs.activity == rhs.activity && lhs.topics == rhs.topics && lhs.summary == rhs.summary && lhs.lastAssistantText == rhs.lastAssistantText
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

    /// Provider for Cursor IDE agent sessions (nil disables Cursor discovery).
    private let cursorProvider: CursorSessionProvider?

    /// Base directory for Claude Code projects.
    private let claudeProjectsDir: URL

    /// Metadata for an active session read from ~/.claude/sessions/*.json.
    struct ActiveSessionMeta {
        let cwd: String      // Working directory from the session JSON
        let startedAt: Date  // When the session was started
    }

    /// Closure that returns active session metas keyed by session ID.
    private let activeSessionMetasProvider: () -> [String: ActiveSessionMeta]

    /// Create a session monitor.
    /// - Parameters:
    ///   - claudeProjectsDir: Override the default `~/.claude/projects` directory (useful for testing).
    ///   - activeSessionMetas: Override the active-session lookup (useful for testing).
    ///   - cursorProvider: Cursor session provider, or `nil` to disable. Defaults to a real provider.
    init(
        claudeProjectsDir: URL? = nil,
        activeSessionMetas: (() -> [String: ActiveSessionMeta])? = nil,
        cursorProvider: CursorSessionProvider? = CursorSessionProvider()
    ) {
        self.claudeProjectsDir = claudeProjectsDir ?? {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return home.appendingPathComponent(".claude/projects", isDirectory: true)
        }()
        self.activeSessionMetasProvider = activeSessionMetas ?? Self.activeSessionMetas
        self.cursorProvider = cursorProvider
    }

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
    func discoverSessions() -> [Session] {
        let fm = FileManager.default

        let projectDirs = (try? fm.contentsOfDirectory(
            at: claudeProjectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []

        var sessions: [Session] = []
        let now = Date()

        let activeMetas = self.activeSessionMetasProvider()
        let activeSessionIDs = Set(activeMetas.keys)

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
                    // Carry forward previous topics/summary when the new scan found none
                    // (assistant output can push user messages out of the tail window)
                    if let cached = scanCache[sessionID] {
                        let topics = fresh.topics.isEmpty ? cached.result.topics : fresh.topics
                        let summary = fresh.summary.isEmpty ? cached.result.summary : fresh.summary
                        if topics != fresh.topics || summary != fresh.summary {
                            fresh = ScanResult(activity: fresh.activity, topics: topics, summary: summary, lastAssistantText: fresh.lastAssistantText)
                        }
                    }
                    result = fresh
                    scanCache[sessionID] = (fileSize: fileSize, result: result)
                }

                sessions.append(Session(
                    id: sessionID,
                    projectName: projectName,
                    activity: result.activity,
                    topics: result.topics,
                    summary: result.summary,
                    lastModified: modified,
                    idleDuration: now.timeIntervalSince(modified),
                    lastAssistantText: result.lastAssistantText
                ))
            }
        }

        // Create synthetic sessions for active processes that have no JSONL file yet
        // (e.g. a freshly opened Claude window before the user sends the first message).
        let discoveredIDs = Set(sessions.map(\.id))
        for (sessionID, meta) in activeMetas where !discoveredIDs.contains(sessionID) {
            let projectName = Self.extractProjectName(fromCwd: meta.cwd)
            sessions.append(Session(
                id: sessionID,
                projectName: projectName,
                activity: .sleeping,
                topics: [],
                summary: "",
                lastModified: meta.startedAt,
                idleDuration: now.timeIntervalSince(meta.startedAt),
                lastAssistantText: nil
            ))
        }

        // Merge Cursor agent sessions
        if let cursorProvider {
            let cursorSessions = cursorProvider.discoverSessions(now: now)
            sessions.append(contentsOf: cursorSessions)
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

    /// Extract human-readable project name from a working directory path.
    /// "/Users/gui/github/background" → "background"
    static func extractProjectName(fromCwd cwd: String) -> String {
        guard !cwd.isEmpty else { return "unknown" }
        return URL(fileURLWithPath: cwd).lastPathComponent
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
        "me", "my", "and", "or", "but", "not", "just", "also", "some", "all",
        "i", "you", "we", "he", "she", "they", "your", "our", "their",
        "its", "do", "does", "did", "have", "has", "had", "be", "been",
        "so", "if", "when", "then", "now", "how", "what", "which", "there"
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

    /// Characters to strip from leading/trailing edges of words.
    private static let edgePunctuation = CharacterSet.alphanumerics.inverted

    /// Strip leading and trailing punctuation from a word, preserving internal chars (e.g. hyphens).
    private static func trimPunctuation(_ word: String) -> String {
        var s = word
        while let first = s.unicodeScalars.first, edgePunctuation.contains(first) {
            s = String(s.dropFirst())
        }
        while let last = s.unicodeScalars.last, edgePunctuation.contains(last) {
            s = String(s.dropLast())
        }
        return s
    }

    /// Split a line into cleaned, lowercased words with edge punctuation stripped.
    private static func cleanWords(_ line: String) -> [String] {
        line.lowercased()
            .components(separatedBy: .whitespaces)
            .map { trimPunctuation($0) }
            .filter { !$0.isEmpty }
    }

    /// Extract a short topic from the user's message using keyword-based extraction.
    /// Scans all lines for the best action-verb match, falls back to meaningful words.
    static func extractTopic(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let messageLines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Try each line for an action-verb match (best signal)
        for line in messageLines {
            let stripped = stripNoise(line)
            guard !stripped.isEmpty else { continue }
            let words = cleanWords(stripped)
            if let result = extractVerbPhrase(from: words) {
                return capTopic(result)
            }
        }

        // No verb found on any line: take meaningful words from the first non-empty line
        for line in messageLines {
            let stripped = stripNoise(line)
            guard !stripped.isEmpty else { continue }
            let words = cleanWords(stripped)
            let meaningful = words.filter { !stopWords.contains($0) }.prefix(4)
            if !meaningful.isEmpty {
                return capTopic(meaningful.joined(separator: " "))
            }
        }

        return ""
    }

    /// Extract a short keyword summary from text using NLTagger lexical classification.
    /// Returns nouns, verbs, and adjectives (3+ chars) joined as a lowercase phrase.
    private static func summarize(_ text: String, maxWords: Int = 5) -> String {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var keywords: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if let tag, [.noun, .verb, .adjective].contains(tag) {
                let word = String(text[range]).lowercased()
                if word.count >= 3, !keywords.contains(word) {
                    keywords.append(word)
                }
            }
            return keywords.count < maxWords
        }
        return keywords.joined(separator: " ")
    }

    /// Strip prompt characters and filler prefixes from a line.
    private static func stripNoise(_ line: String) -> String {
        var stripped = line
        // Strip leading prompt characters
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
        return stripped
    }

    /// Extract a "verb + up to 3 objects" phrase if an action verb is found.
    private static func extractVerbPhrase(from words: [String]) -> String? {
        guard let verbIndex = words.firstIndex(where: { actionVerbs.contains($0) }) else {
            return nil
        }
        var collected = [words[verbIndex]]
        for word in words[(verbIndex + 1)...] {
            if collected.count >= 4 { break }
            if !stopWords.contains(word) {
                collected.append(word)
            }
        }
        return collected.joined(separator: " ")
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

    /// Read ~/.claude/sessions/*.json to get metadata for currently running Claude processes.
    private static func activeSessionMetas() -> [String: ActiveSessionMeta] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessionsDir = home.appendingPathComponent(".claude/sessions", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [:] }

        var result: [String: ActiveSessionMeta] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionId = json["sessionId"] as? String,
                  let pid = json["pid"] as? Int else { continue }

            guard kill(pid_t(pid), 0) == 0 else {
                try? FileManager.default.removeItem(at: file)
                continue
            }

            let cwd = json["cwd"] as? String ?? ""
            let startedAtMs = json["startedAt"] as? Double ?? 0
            let startedAt = Date(timeIntervalSince1970: startedAtMs / 1000.0)
            result[sessionId] = ActiveSessionMeta(cwd: cwd, startedAt: startedAt)
        }
        return result
    }

    struct ScanResult {
        let activity: Activity
        let topics: [String]
        let summary: String
        let lastAssistantText: String?
    }

    /// Read tail of a JSONL file, classify activity and extract topics.
    static func classifyActivity(fileURL: URL, lastModified: Date, now: Date) -> ScanResult {
        let empty = ScanResult(activity: .sleeping, topics: [], summary: "", lastAssistantText: nil)

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return empty }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()

        // Activity classification: small tail (64KB) — only recent lines matter.
        let activityTailBytes = 64 * 1024
        let activityOffset = fileSize > UInt64(activityTailBytes) ? fileSize - UInt64(activityTailBytes) : 0
        handle.seek(toFileOffset: activityOffset)
        let activityData = handle.availableData
        guard let activityContent = String(data: activityData, encoding: .utf8) else {
            return empty
        }

        let lines = activityContent.components(separatedBy: .newlines)
            .suffix(120)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(100)

        // Topic + summary extraction: wider tail (512KB) — user messages are sparse among tool output.
        let extracted = extractTopics(handle: handle, fileSize: fileSize)

        var activity: Activity = .sleeping
        var lastAssistantText: String?

        var sawSessionReset = false
        // Track whether we've seen a tool_result after the most recent assistant tool_use.
        // Walking backwards: if we hit an assistant tool_use before seeing any tool_result,
        // the tool hasn't executed yet — the session is waiting for user permission.
        var sawToolResult = false

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

            // Track tool_result messages (appear as user messages with tool_result content blocks,
            // or as tool_result type entries). These come after the assistant's tool_use in the file,
            // so we see them first when walking backwards.
            if activity == .sleeping, !sawToolResult {
                if type == "tool_result" {
                    sawToolResult = true
                } else if type == "user",
                          let message = json["message"] as? [String: Any],
                          let blocks = message["content"] as? [[String: Any]] {
                    let hasToolResult = blocks.contains { $0["type"] as? String == "tool_result" }
                    if hasToolResult { sawToolResult = true }
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
                           block["name"] as? String == "AskUserQuestion",
                           let input = block["input"] as? [String: Any],
                           let q = input["question"] as? String {
                            isAsking = true
                            lastAssistantText = q
                            break
                        }
                        if block["type"] as? String == "text",
                           let text = block["text"] as? String {
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            // Check the last paragraph for a question mark — agents often
                            // ask a question then add a short clarifying note after it.
                            let lastParagraph: Substring
                            if let range = trimmed.range(of: "\n\n", options: .backwards) {
                                lastParagraph = trimmed[range.upperBound...]
                            } else {
                                lastParagraph = trimmed[...]
                            }
                            if lastParagraph.contains("?") {
                                isAsking = true
                            }
                            lastAssistantText = text
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

                // Capture the last text block from this assistant message
                if let lastText = blocks.last(where: { $0["type"] as? String == "text" })?["text"] as? String,
                   !lastText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lastAssistantText = lastText
                }

                // Check if AskUserQuestion was called — always counts as asking
                let hasAskUser = blocks.contains {
                    $0["type"] as? String == "tool_use" && $0["name"] as? String == "AskUserQuestion"
                }

                if hasAskUser {
                    activity = .asking
                    // Extract the question text from AskUserQuestion input
                    if let askBlock = blocks.first(where: { $0["name"] as? String == "AskUserQuestion" }),
                       let input = askBlock["input"] as? [String: Any],
                       let q = input["question"] as? String {
                        lastAssistantText = q
                    }
                } else if !toolNames.isEmpty {
                    // If no tool_result followed this tool_use, the tool hasn't been
                    // approved/executed yet — the session is waiting for user permission.
                    if !sawToolResult {
                        activity = .asking
                        // Build a meaningful summary of what tool is pending approval
                        if lastAssistantText == nil {
                            lastAssistantText = Self.pendingToolSummary(blocks: blocks)
                        }
                    } else {
                        let toolSet = Set(toolNames)
                        if toolSet.contains("Bash") {
                            activity = Self.classifyBashCommand(blocks: blocks)
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
                    }
                } else {
                    let hasText = blocks.contains { $0["type"] as? String == "text" }
                    if hasText {
                        activity = .thinking
                    }
                }
            }

            // User message — session is active, agent is processing input
            if activity == .sleeping, type == "user" {
                activity = .processing
            }
        }

        return ScanResult(activity: activity, topics: extracted.topics.reversed(), summary: extracted.summary, lastAssistantText: lastAssistantText)
    }

    // MARK: - Topic Extraction (wide scan)

    /// Extract up to 3 topics and a keyword summary from user messages, scanning a wider tail (512KB).
    /// Only parses lines that look like user messages (fast string pre-filter).
    private static func extractTopics(handle: FileHandle, fileSize: UInt64) -> (topics: [String], summary: String) {
        let topicTailBytes = 512 * 1024
        let topicOffset = fileSize > UInt64(topicTailBytes) ? fileSize - UInt64(topicTailBytes) : 0
        handle.seek(toFileOffset: topicOffset)
        let topicData = handle.availableData
        guard let topicContent = String(data: topicData, encoding: .utf8) else { return ([], "") }

        // Pre-filter: only parse lines that contain "type":"user" (avoids parsing huge tool_result lines)
        let candidateLines = topicContent.components(separatedBy: .newlines)
            .filter { $0.contains("\"type\":\"user\"") }

        var topics: [String] = []
        var summary = ""

        // Walk backwards through candidate lines (most recent first)
        for line in candidateLines.reversed() {
            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  json["type"] as? String == "user",
                  let message = json["message"] as? [String: Any] else { continue }

            // Extract text content (plain string or structured blocks)
            let msgContent: String? = {
                if let str = message["content"] as? String { return str }
                if let blocks = message["content"] as? [[String: Any]] {
                    let texts = blocks.compactMap { block -> String? in
                        guard block["type"] as? String == "text" else { return nil }
                        return block["text"] as? String
                    }
                    return texts.isEmpty ? nil : texts.joined(separator: " ")
                }
                return nil
            }()

            if let content = msgContent {
                // Summarize the most recent meaningful user message
                if summary.isEmpty {
                    let s = Self.summarize(content)
                    if !s.isEmpty { summary = s }
                }

                if topics.count < 3 {
                    let extracted = Self.extractTopic(from: content)
                    if extracted.count >= 5, extracted.contains(" "),
                       !topics.contains(where: { $0.lowercased() == extracted.lowercased() }) {
                        topics.append(extracted)
                    }
                }

                // Stop once we have both summary and enough topics
                if !summary.isEmpty, topics.count >= 3 { break }
            }
        }

        return (topics: topics.reversed(), summary: summary)  // topics: oldest first
    }

    // MARK: - Bash Command Classification

    /// Patterns for git commands.
    private static let gitPatterns = [
        "git commit", "git push", "git add", "git merge", "git rebase",
        "git cherry-pick", "git tag", "git stash", "git pull", "git fetch",
        "git checkout", "git switch", "git branch", "git reset", "git revert",
        "git diff", "git log", "git status", "git am", "git format-patch"
    ]

    /// Patterns for test commands.
    private static let testPatterns = [
        "npm test", "npm run test", "npx jest", "npx vitest", "npx mocha",
        "yarn test", "pnpm test", "bun test",
        "pytest", "python -m pytest", "python -m unittest",
        "cargo test", "go test", "swift test",
        "xcodebuild test", "xctest",
        "rspec", "bundle exec rspec", "rake test", "rake spec",
        "dotnet test", "mvn test", "gradle test",
        "make test", "make check"
    ]

    /// Patterns for build/compile commands.
    private static let buildPatterns = [
        "npm run build", "npx webpack", "npx tsc", "npx vite build",
        "yarn build", "pnpm build", "bun build",
        "cargo build", "cargo clippy", "rustc",
        "go build", "go install",
        "swift build", "xcodebuild", "xcodebuild -scheme",
        "make", "cmake", "ninja",
        "gcc", "g++", "clang", "clang++", "javac",
        "dotnet build", "mvn compile", "mvn package", "gradle build",
        "docker build", "tsc"
    ]

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

    /// Inspect Bash tool_use blocks to classify the command being run.
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

    /// Build a human-readable summary of the pending tool awaiting permission.
    private static func pendingToolSummary(blocks: [[String: Any]]) -> String? {
        // Walk backwards to find the last tool_use block
        for block in blocks.reversed() {
            guard block["type"] as? String == "tool_use",
                  let name = block["name"] as? String,
                  let input = block["input"] as? [String: Any] else { continue }

            switch name {
            case "Bash":
                if let cmd = input["command"] as? String {
                    let first = cmd.components(separatedBy: .newlines).first ?? cmd
                    let trimmed = first.trimmingCharacters(in: .whitespaces)
                    return "Run: \(trimmed)"
                }
            case "Edit", "Write", "Read":
                if let path = input["file_path"] as? String {
                    let file = (path as NSString).lastPathComponent
                    return "\(name): \(file)"
                }
            case "Agent":
                if let desc = input["description"] as? String {
                    return "Agent: \(desc)"
                }
            default:
                break
            }
            return "Approve: \(name)"
        }
        return nil
    }
}
