import XCTest
@testable import MacosDefaultsCore

final class StateFileTests: XCTestCase {
    func testParseAllTypes() throws {
        let text = """
        com.apple.finder\tShowPathbar\tbool\ttrue
        com.apple.dock\ttilesize\tint\t48
        NSGlobalDomain\tcom.apple.springing.delay\tfloat\t0.5
        com.apple.finder\tFXPreferredViewStyle\tstring\tNlsv
        """
        let entries = try StateFile.parse(text)
        XCTAssertEqual(entries, [
            StateEntry(domain: "com.apple.finder", key: "ShowPathbar", value: .bool(true)),
            StateEntry(domain: "com.apple.dock", key: "tilesize", value: .int(48)),
            StateEntry(domain: "NSGlobalDomain", key: "com.apple.springing.delay", value: .double(0.5)),
            StateEntry(domain: "com.apple.finder", key: "FXPreferredViewStyle", value: .string("Nlsv")),
        ])
    }

    func testParseIgnoresBlankAndComments() throws {
        let text = """
        # a comment
        com.apple.finder\tShowPathbar\tbool\ttrue

        # another
        """
        let entries = try StateFile.parse(text)
        XCTAssertEqual(entries.count, 1)
    }

    func testStringValueWithSpacesAndDots() throws {
        let text = "com.example\tsome.key with spaces\tstring\tvalue with spaces"
        let entries = try StateFile.parse(text)
        XCTAssertEqual(entries[0].key, "some.key with spaces")
        XCTAssertEqual(entries[0].value, .string("value with spaces"))
    }

    func testEmitSortsByDomainThenKey() {
        let entries = [
            StateEntry(domain: "com.apple.finder", key: "ShowPathbar", value: .bool(true)),
            StateEntry(domain: "com.apple.dock", key: "tilesize", value: .int(48)),
            StateEntry(domain: "com.apple.finder", key: "AppleShowAllFiles", value: .bool(false)),
        ]
        let text = StateFile.emit(entries)
        XCTAssertEqual(text, """
        com.apple.dock\ttilesize\tint\t48
        com.apple.finder\tAppleShowAllFiles\tbool\tfalse
        com.apple.finder\tShowPathbar\tbool\ttrue
        """ + "\n")
    }

    func testRoundTrip() throws {
        let entries = [
            StateEntry(domain: "d", key: "b", value: .bool(false)),
            StateEntry(domain: "d", key: "i", value: .int(-3)),
            StateEntry(domain: "d", key: "f", value: .double(2.25)),
            StateEntry(domain: "d", key: "s", value: .string("hi there")),
        ]
        let reparsed = try StateFile.parse(StateFile.emit(entries))
        XCTAssertEqual(reparsed, entries.sorted { ($0.domain, $0.key) < ($1.domain, $1.key) })
    }

    func testMalformedWrongFieldCount() {
        XCTAssertThrowsError(try StateFile.parse("com.apple.finder\tShowPathbar\tbool")) { error in
            guard case StateFileError.malformedLine(let line, _, _) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(line, 1)
        }
    }

    func testMalformedUnknownType() {
        XCTAssertThrowsError(try StateFile.parse("d\tk\tdict\t{}")) { error in
            guard case StateFileError.malformedLine(let line, _, let reason) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(line, 1)
            XCTAssertTrue(reason.contains("type"))
        }
    }

    func testMalformedUnparsableValueReportsLineNumber() {
        let text = "d\tk\tbool\ttrue\nd\tk2\tint\tnotanint"
        XCTAssertThrowsError(try StateFile.parse(text)) { error in
            guard case StateFileError.malformedLine(let line, _, _) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(line, 2)
        }
    }
}
