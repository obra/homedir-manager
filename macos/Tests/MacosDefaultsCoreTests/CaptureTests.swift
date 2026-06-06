import XCTest
@testable import MacosDefaultsCore

final class CaptureTests: XCTestCase {
    func testCaptureExplicitKeys() {
        let store = FakePreferencesStore()
        try! store.set(.bool(true), forKey: "ShowPathbar", inDomain: "com.apple.finder")
        try! store.set(.int(48), forKey: "tilesize", inDomain: "com.apple.finder")
        let result = captureEntries(domain: "com.apple.finder",
                                    keys: ["tilesize", "ShowPathbar"],
                                    store: store, noise: nil)
        // Entries sorted by (domain, key) on emit.
        XCTAssertEqual(result.entries, [
            StateEntry(domain: "com.apple.finder", key: "ShowPathbar", value: .bool(true)),
            StateEntry(domain: "com.apple.finder", key: "tilesize", value: .int(48)),
        ])
        XCTAssertTrue(result.skips.isEmpty)
    }

    func testCaptureExplicitMissingKeyIsSkipped() {
        let store = FakePreferencesStore()
        let result = captureEntries(domain: "d", keys: ["nope"], store: store, noise: nil)
        XCTAssertTrue(result.entries.isEmpty)
        // A missing explicit key produces no entry and no SKIP (it simply has no value).
        XCTAssertTrue(result.skips.isEmpty)
    }

    func testCaptureExplicitUnsupportedKeyIsSkipped() {
        let store = FakePreferencesStore()
        store.seed(.unsupported("CFArray"), forKey: "list", inDomain: "d")
        let result = captureEntries(domain: "d", keys: ["list"], store: store, noise: nil)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.skips[0].line, "SKIP d list (unsupported type: CFArray)")
    }

    func testCaptureStringWithTabIsSkipped() {
        let store = FakePreferencesStore()
        store.seed(.string("a\tb"), forKey: "k", inDomain: "d")
        let result = captureEntries(domain: "d", keys: ["k"], store: store, noise: nil)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.skips[0].line,
            "SKIP d k (unsupported: string contains TAB or newline)")
    }

    func testCaptureStringWithNewlineIsSkipped() {
        let store = FakePreferencesStore()
        store.seed(.string("a\nb"), forKey: "k", inDomain: "d")
        let result = captureEntries(domain: "d", keys: ["k"], store: store, noise: nil)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.skips.count, 1)
        XCTAssertEqual(result.skips[0].line,
            "SKIP d k (unsupported: string contains TAB or newline)")
    }

    func testNoiseIgnoredForExplicitKeys() {
        let store = FakePreferencesStore()
        try! store.set(.int(1), forKey: "Window Frame", inDomain: "d")
        // "Window Frame" matches the noise pattern, but because it's an explicit key it is
        // still captured — noise only filters whole-domain capture.
        let result = captureEntries(domain: "d", keys: ["Window Frame"], store: store,
                                    noise: NoiseFilter(patterns: ["* Frame"]))
        XCTAssertEqual(result.entries,
            [StateEntry(domain: "d", key: "Window Frame", value: .int(1))])
        XCTAssertTrue(result.skips.isEmpty)
    }

    func testCaptureWholeDomainAppliesNoise() {
        let store = FakePreferencesStore()
        try! store.set(.int(1), forKey: "tilesize", inDomain: "d")
        try! store.set(.int(2), forKey: "Window Frame", inDomain: "d")
        let result = captureEntries(domain: "d", keys: [], store: store,
                                    noise: NoiseFilter(patterns: ["* Frame"]))
        XCTAssertEqual(result.entries.map(\.key), ["tilesize"])
    }

    func testCaptureWholeDomainNoNoise() {
        let store = FakePreferencesStore()
        try! store.set(.int(1), forKey: "b", inDomain: "d")
        try! store.set(.int(2), forKey: "a", inDomain: "d")
        let result = captureEntries(domain: "d", keys: [], store: store, noise: nil)
        XCTAssertEqual(result.entries.map(\.key), ["a", "b"])
    }
}
