import XCTest
import Foundation
import CoreFoundation
@testable import MacosDefaultsCore

final class ClassifyTests: XCTestCase {
    func testBool() {
        XCTAssertEqual(classifyCFValue(kCFBooleanTrue), .bool(true))
        XCTAssertEqual(classifyCFValue(kCFBooleanFalse), .bool(false))
    }

    func testInt() {
        XCTAssertEqual(classifyCFValue(NSNumber(value: 42)), .int(42))
        XCTAssertEqual(classifyCFValue(NSNumber(value: -7)), .int(-7))
    }

    func testFloat() {
        XCTAssertEqual(classifyCFValue(NSNumber(value: 1.5)), .double(1.5))
    }

    func testString() {
        XCTAssertEqual(classifyCFValue("hello" as CFString), .string("hello"))
    }

    func testUnsupportedArray() {
        guard case .unsupported(let name) = classifyCFValue([1, 2] as CFArray) else {
            return XCTFail("expected unsupported")
        }
        XCTAssertEqual(name, "CFArray")
    }

    func testUnsupportedDictionary() {
        guard case .unsupported(let name) = classifyCFValue(["a": "b"] as CFDictionary) else {
            return XCTFail("expected unsupported")
        }
        XCTAssertEqual(name, "CFDictionary")
    }

    func testUnsupportedDate() {
        guard case .unsupported = classifyCFValue(Date() as CFDate) else {
            return XCTFail("expected unsupported")
        }
    }

    func testUnsupportedData() {
        guard case .unsupported = classifyCFValue(Data([0x01]) as CFData) else {
            return XCTFail("expected unsupported")
        }
    }
}
