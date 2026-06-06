import XCTest
@testable import MacosDefaultsCore

final class NoiseFilterTests: XCTestCase {
    func testStarMatches() {
        let f = NoiseFilter(patterns: ["* Frame", "*Recent*", "NSWindow Frame *"])
        XCTAssertTrue(f.matches("Browser Window Frame"))   // matches "* Frame"
        XCTAssertTrue(f.matches("RecentDocuments"))        // matches "*Recent*"
        XCTAssertTrue(f.matches("NSWindow Frame Main"))    // matches "NSWindow Frame *"
        XCTAssertFalse(f.matches("ShowPathbar"))
        XCTAssertFalse(f.matches("tilesize"))
    }

    func testQuestionMarkAndClasses() {
        let f = NoiseFilter(patterns: ["key?", "v[0-9]"])
        XCTAssertTrue(f.matches("key1"))
        XCTAssertFalse(f.matches("key"))      // ? requires exactly one char
        XCTAssertTrue(f.matches("v3"))
        XCTAssertFalse(f.matches("vx"))
    }

    func testEmptyFilterMatchesNothing() {
        let f = NoiseFilter(patterns: [])
        XCTAssertFalse(f.matches("anything"))
    }

    func testParseLineListIgnoresCommentsAndBlanks() {
        let text = """
        # comment
        com.apple.finder

        NSGlobalDomain
        """
        XCTAssertEqual(parseLineList(text), ["com.apple.finder", "NSGlobalDomain"])
    }
}
