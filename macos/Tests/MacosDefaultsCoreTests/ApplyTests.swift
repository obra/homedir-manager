import XCTest
@testable import MacosDefaultsCore

final class ApplyTests: XCTestCase {
    func testApplyWritesEachEntry() throws {
        let store = FakePreferencesStore()
        let entries = [
            StateEntry(domain: "com.apple.dock", key: "tilesize", value: .int(48)),
            StateEntry(domain: "com.apple.finder", key: "ShowPathbar", value: .bool(true)),
        ]
        try applyEntries(entries, store: store)
        XCTAssertEqual(store.value(forKey: "tilesize", inDomain: "com.apple.dock"), .int(48))
        XCTAssertEqual(store.value(forKey: "ShowPathbar", inDomain: "com.apple.finder"), .bool(true))
    }

    func testApplyIsIdempotent() throws {
        let store = FakePreferencesStore()
        let entries = [StateEntry(domain: "d", key: "k", value: .int(1))]
        try applyEntries(entries, store: store)
        try applyEntries(entries, store: store)
        XCTAssertEqual(store.value(forKey: "k", inDomain: "d"), .int(1))
    }

    func testApplyFailsFastOnWriteError() {
        let store = FakePreferencesStore()
        store.failOnSet = true
        let entries = [StateEntry(domain: "d", key: "k", value: .int(1))]
        XCTAssertThrowsError(try applyEntries(entries, store: store)) { error in
            guard let writeError = error as? PreferencesWriteError else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(writeError.key, "k")
        }
    }
}
