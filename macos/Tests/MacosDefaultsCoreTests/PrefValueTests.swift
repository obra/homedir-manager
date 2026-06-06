import XCTest
@testable import MacosDefaultsCore

final class PrefValueTests: XCTestCase {
    func testTypeTokens() {
        XCTAssertEqual(PrefValue.bool(true).typeToken, "bool")
        XCTAssertEqual(PrefValue.int(1).typeToken, "int")
        XCTAssertEqual(PrefValue.double(1.5).typeToken, "float")
        XCTAssertEqual(PrefValue.string("x").typeToken, "string")
        XCTAssertEqual(PrefValue.unsupported("CFArray").typeToken, "unsupported")
    }

    func testSerialized() {
        XCTAssertEqual(PrefValue.bool(true).serialized, "true")
        XCTAssertEqual(PrefValue.bool(false).serialized, "false")
        XCTAssertEqual(PrefValue.int(42).serialized, "42")
        XCTAssertEqual(PrefValue.int(-7).serialized, "-7")
        XCTAssertEqual(PrefValue.double(1.5).serialized, "1.5")
        XCTAssertEqual(PrefValue.double(0.1).serialized, "0.1")
        XCTAssertEqual(PrefValue.string("hello world").serialized, "hello world")
        XCTAssertEqual(PrefValue.unsupported("CFArray").serialized, "<unsupported CFArray>")
    }
}
