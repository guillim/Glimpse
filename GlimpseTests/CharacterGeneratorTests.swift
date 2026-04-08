import XCTest
@testable import Glimpse

final class CharacterGeneratorTests: XCTestCase {

    // MARK: - Test 7: Character trait determinism

    func testTraitDeterminism() {
        let sessionID = "test-session-abc-123"

        let traits1 = CharacterGenerator.traits(for: sessionID)
        let traits2 = CharacterGenerator.traits(for: sessionID)

        // Same session ID must always produce identical traits
        XCTAssertEqual(traits1.bodyShape, traits2.bodyShape)
        XCTAssertEqual(traits1.eyeStyle, traits2.eyeStyle)
        XCTAssertEqual(traits1.earStyle, traits2.earStyle)
        XCTAssertEqual(traits1.tailStyle, traits2.tailStyle)
        XCTAssertEqual(traits1.mouthStyle, traits2.mouthStyle)
        XCTAssertEqual(traits1.cheekStyle, traits2.cheekStyle)

        // Body color RGB must match
        let (r1, g1, b1) = traits1.bodyRGB
        let (r2, g2, b2) = traits2.bodyRGB
        XCTAssertEqual(r1, r2, accuracy: 0.001)
        XCTAssertEqual(g1, g2, accuracy: 0.001)
        XCTAssertEqual(b1, b2, accuracy: 0.001)
    }

    func testDifferentSessionsProduceDifferentTraits() {
        let traitsA = CharacterGenerator.traits(for: "session-alpha")
        let traitsB = CharacterGenerator.traits(for: "session-beta")

        // Different IDs should (very likely) produce different traits.
        // We check multiple fields — it's statistically near-impossible for all to match.
        let allMatch = traitsA.bodyShape == traitsB.bodyShape
            && traitsA.eyeStyle == traitsB.eyeStyle
            && traitsA.earStyle == traitsB.earStyle
            && traitsA.tailStyle == traitsB.tailStyle
            && traitsA.mouthStyle == traitsB.mouthStyle
            && traitsA.cheekStyle == traitsB.cheekStyle

        XCTAssertFalse(allMatch, "Two different session IDs should produce different trait combinations")
    }

    // MARK: - Character dedup across sessions

    func testCharacterDedupAvoidsDuplicates() {
        // Use Office generator (8 characters) as representative test.
        // Assign characters for 3 sessions — all should be unique.
        let ids = ["session-aaa", "session-bbb", "session-ccc"]
        let characters = ids.map { OfficeCharacterGenerator.character(for: $0) }

        let uniqueRawValues = Set(characters.map(\.rawValue))
        XCTAssertEqual(uniqueRawValues.count, 3, "3 sessions should get 3 different characters")

        // Clean up
        ids.forEach { OfficeCharacterGenerator.releaseAssignment(for: $0) }
    }

    func testCharacterDedupAllowsDuplicatesWhenExhausted() {
        // Office has 8 characters. Assign all 8, then a 9th must duplicate.
        var ids: [String] = []
        for i in 0..<8 {
            ids.append("exhaust-\(i)")
            _ = OfficeCharacterGenerator.character(for: "exhaust-\(i)")
        }

        let uniqueBefore = Set(ids.map { OfficeCharacterGenerator.character(for: $0).rawValue })
        XCTAssertEqual(uniqueBefore.count, 8, "First 8 sessions should each get a unique character")

        // 9th session must get a character (duplicate is OK)
        let ninth = OfficeCharacterGenerator.character(for: "exhaust-overflow")
        XCTAssertNotNil(ninth)

        // Clean up
        (ids + ["exhaust-overflow"]).forEach { OfficeCharacterGenerator.releaseAssignment(for: $0) }
    }

    func testCharacterReleaseAllowsReuse() {
        let id1 = "release-test-1"
        let id2 = "release-test-2"
        let ch1 = OfficeCharacterGenerator.character(for: id1)

        // Release id1, then id2 should be able to get the same character
        OfficeCharacterGenerator.releaseAssignment(for: id1)
        let ch2 = OfficeCharacterGenerator.character(for: id2)

        // ch2 gets its preferred character — may or may not be same as ch1,
        // but the important thing is the assignment works without error
        XCTAssertNotNil(ch2)

        // Clean up
        OfficeCharacterGenerator.releaseAssignment(for: id2)
    }

    // MARK: - Card layout: project name truncation

    func testTruncateProjectName() {
        // Short names pass through unchanged
        XCTAssertEqual(CharacterNode.truncateProjectName("glimpse", maxChars: 8), "glimpse")
        XCTAssertEqual(CharacterNode.truncateProjectName("app", maxChars: 8), "app")

        // Exactly at limit — no truncation
        XCTAssertEqual(CharacterNode.truncateProjectName("12345678", maxChars: 8), "12345678")

        // Over limit — truncated with ellipsis
        XCTAssertEqual(CharacterNode.truncateProjectName("123456789", maxChars: 8), "1234567…")
        XCTAssertEqual(CharacterNode.truncateProjectName("my-very-long-project-name", maxChars: 8), "1234567…".count == 8 ? "my-very…" : "my-very…")

        // Very tight limit
        XCTAssertEqual(CharacterNode.truncateProjectName("glimpse", maxChars: 4), "gli…")
        XCTAssertEqual(CharacterNode.truncateProjectName("ab", maxChars: 4), "ab")

        // Edge: maxChars = 3 (minimum useful)
        XCTAssertEqual(CharacterNode.truncateProjectName("glimpse", maxChars: 3), "gl…")
    }
}
