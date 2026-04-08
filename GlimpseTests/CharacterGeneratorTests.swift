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
