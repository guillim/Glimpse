import XCTest
@testable import Glimpse

final class SessionMonitorTests: XCTestCase {

    // MARK: - Test 1: extractProjectName

    func testExtractProjectName() {
        XCTAssertEqual(SessionMonitor.extractProjectName(from: "-Users-gui-github-background"), "background")
        XCTAssertEqual(SessionMonitor.extractProjectName(from: "-Users-gui-github-glimpse"), "glimpse")
        XCTAssertEqual(SessionMonitor.extractProjectName(from: "single"), "single")
        XCTAssertEqual(SessionMonitor.extractProjectName(from: "-Users-gui-my-project"), "project")
    }

    // MARK: - Test 2: extractTopic

    func testExtractTopic() {
        // Action verb extraction
        XCTAssertEqual(SessionMonitor.extractTopic(from: "fix the login bug"), "fix login bug")
        XCTAssertEqual(SessionMonitor.extractTopic(from: "add dark mode support"), "add dark mode support")

        // Filler prefix stripping
        XCTAssertEqual(SessionMonitor.extractTopic(from: "can you fix the auth module"), "fix auth module")
        XCTAssertEqual(SessionMonitor.extractTopic(from: "please add a new endpoint"), "add new endpoint")

        // Falls back to meaningful words when no action verb
        let topic = SessionMonitor.extractTopic(from: "the authentication module needs work")
        XCTAssertFalse(topic.isEmpty)

        // Empty input
        XCTAssertEqual(SessionMonitor.extractTopic(from: ""), "")
    }

    // MARK: - Test 3: classifyTerminalCommand

    func testClassifyTerminalCommand() {
        // Git operations
        XCTAssertEqual(SessionMonitor.classifyTerminalCommand("git commit -m 'test'"), .committing)
        XCTAssertEqual(SessionMonitor.classifyTerminalCommand("git push origin main"), .committing)
        XCTAssertEqual(SessionMonitor.classifyTerminalCommand("git status"), .committing)

        // Test commands
        XCTAssertEqual(SessionMonitor.classifyTerminalCommand("npm test"), .testing)
        XCTAssertEqual(SessionMonitor.classifyTerminalCommand("pytest -v"), .testing)
        XCTAssertEqual(SessionMonitor.classifyTerminalCommand("cargo test"), .testing)
        XCTAssertEqual(SessionMonitor.classifyTerminalCommand("swift test"), .testing)

        // Build commands
        XCTAssertEqual(SessionMonitor.classifyTerminalCommand("npm run build"), .building)
        XCTAssertEqual(SessionMonitor.classifyTerminalCommand("cargo build"), .building)
        XCTAssertEqual(SessionMonitor.classifyTerminalCommand("xcodebuild"), .building)

        // Generic commands
        XCTAssertEqual(SessionMonitor.classifyTerminalCommand("ls -la"), .running)
        XCTAssertEqual(SessionMonitor.classifyTerminalCommand("echo hello"), .running)
    }

    // MARK: - Test 4: classifyActivity from JSONL

    func testClassifyActivityFromJSONL() throws {
        // Create a mock JSONL file with a tool_use for reading.
        // The tool_result after the assistant message signals that the tool was approved and executed.
        let jsonl = """
        {"type":"user","message":{"content":"check the files"}}
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","id":"t1","input":{"file_path":"/tmp/test.swift"}}]}}
        {"type":"tool_result","tool_use_id":"t1","content":"file contents here"}
        """

        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        try jsonl.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let result = SessionMonitor.classifyActivity(fileURL: tmpFile, lastModified: Date(), now: Date())
        XCTAssertEqual(result.activity, .reading)
    }

    func testClassifyActivityWriting() throws {
        let jsonl = """
        {"type":"user","message":{"content":"edit the file"}}
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","id":"t1","input":{"file_path":"/tmp/test.swift","old_string":"a","new_string":"b"}}]}}
        {"type":"tool_result","tool_use_id":"t1","content":"ok"}
        """

        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        try jsonl.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let result = SessionMonitor.classifyActivity(fileURL: tmpFile, lastModified: Date(), now: Date())
        XCTAssertEqual(result.activity, .writing)
    }

    func testClassifyActivityDone() throws {
        let jsonl = """
        {"type":"user","message":{"content":"hello"}}
        {"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"All done."}]}}
        """

        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        try jsonl.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let result = SessionMonitor.classifyActivity(fileURL: tmpFile, lastModified: Date(), now: Date())
        XCTAssertEqual(result.activity, .done)
    }

    func testClassifyActivityAsking() throws {
        let jsonl = """
        {"type":"user","message":{"content":"help me"}}
        {"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Would you like me to proceed?"}]}}
        """

        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        try jsonl.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let result = SessionMonitor.classifyActivity(fileURL: tmpFile, lastModified: Date(), now: Date())
        XCTAssertEqual(result.activity, .asking)
    }

    // MARK: - Test 5: discoverSessions finds session from mock directory

    func testDiscoverSessionsFindsSession() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("glimpse-test-\(UUID().uuidString)", isDirectory: true)
        let projectDir = tmpDir.appendingPathComponent("-Users-gui-github-testproject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sessionID = UUID().uuidString
        let jsonlFile = projectDir.appendingPathComponent("\(sessionID).jsonl")
        let jsonl = """
        {"type":"user","message":{"content":"add dark mode"}}
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","id":"t1","input":{"file_path":"/tmp/x.swift","old_string":"a","new_string":"b"}}]}}
        {"type":"tool_result","tool_use_id":"t1","content":"ok"}
        """
        try jsonl.write(to: jsonlFile, atomically: true, encoding: .utf8)

        let monitor = SessionMonitor(
            claudeProjectsDir: tmpDir,
            activeSessionIDs: { [sessionID] },
            cursorProvider: nil
        )

        let sessions = monitor.discoverSessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, sessionID)
        XCTAssertEqual(sessions.first?.projectName, "testproject")
        XCTAssertEqual(sessions.first?.activity, .writing)
    }

    // MARK: - Test 6: discoverSessions handles session removal

    func testDiscoverSessionsHandlesRemoval() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("glimpse-test-\(UUID().uuidString)", isDirectory: true)
        let projectDir = tmpDir.appendingPathComponent("-Users-gui-github-myapp", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sessionID = UUID().uuidString
        let jsonlFile = projectDir.appendingPathComponent("\(sessionID).jsonl")
        let jsonl = """
        {"type":"user","message":{"content":"hello"}}
        {"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Done."}]}}
        """
        try jsonl.write(to: jsonlFile, atomically: true, encoding: .utf8)

        let monitor = SessionMonitor(
            claudeProjectsDir: tmpDir,
            activeSessionIDs: { [sessionID] },
            cursorProvider: nil
        )

        // First scan: session is present
        let sessions1 = monitor.discoverSessions()
        XCTAssertEqual(sessions1.count, 1)

        // Remove the file
        try FileManager.default.removeItem(at: jsonlFile)

        // Second scan: session is gone
        let sessions2 = monitor.discoverSessions()
        XCTAssertEqual(sessions2.count, 0)
    }
}
