import XCTest
@testable import MacosDefaultsCore

final class FakePreferencesStoreTests: XCTestCase {
    func testSetAndRead() throws {
        let store = FakePreferencesStore()
        try store.set(.int(5), forKey: "Count", inDomain: "com.example.app")
        XCTAssertEqual(store.value(forKey: "Count", inDomain: "com.example.app"), .int(5))
    }

    func testUnsetKeyReturnsNil() {
        let store = FakePreferencesStore()
        XCTAssertNil(store.value(forKey: "Missing", inDomain: "com.example.app"))
    }

    func testKeysListsSetKeys() throws {
        let store = FakePreferencesStore()
        try store.set(.bool(true), forKey: "A", inDomain: "d")
        try store.set(.string("x"), forKey: "B", inDomain: "d")
        XCTAssertEqual(store.keys(inDomain: "d").sorted(), ["A", "B"])
        XCTAssertEqual(store.keys(inDomain: "other"), [])
    }

    func testSeedAllowsUnsupportedValues() {
        let store = FakePreferencesStore()
        store.seed(.unsupported("CFArray"), forKey: "List", inDomain: "d")
        XCTAssertEqual(store.value(forKey: "List", inDomain: "d"), .unsupported("CFArray"))
    }

    func testSetThrowingStorePropagates() {
        let store = FakePreferencesStore()
        store.failOnSet = true
        XCTAssertThrowsError(try store.set(.int(1), forKey: "K", inDomain: "d"))
    }
}
