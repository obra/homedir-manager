import XCTest
@testable import MacosDefaultsCore

final class DriftTests: XCTestCase {
    func testDriftedWhenValueDiffers() {
        let store = FakePreferencesStore()
        try! store.set(.int(36), forKey: "tilesize", inDomain: "com.apple.dock")
        let desired = [StateEntry(domain: "com.apple.dock", key: "tilesize", value: .int(48))]
        let result = computeDrift(desired: desired, store: store,
                                  watchedDomains: [], noise: NoiseFilter(patterns: []))
        XCTAssertEqual(result.drifted.count, 1)
        XCTAssertEqual(result.drifted[0].line,
            "DRIFT  com.apple.dock  tilesize  current=36  desired=48")
        XCTAssertTrue(result.untracked.isEmpty)
    }

    func testDriftedWhenUnset() {
        let store = FakePreferencesStore()
        let desired = [StateEntry(domain: "d", key: "k", value: .bool(true))]
        let result = computeDrift(desired: desired, store: store,
                                  watchedDomains: [], noise: NoiseFilter(patterns: []))
        XCTAssertEqual(result.drifted[0].line, "DRIFT  d  k  current=unset  desired=true")
    }

    func testNoDriftWhenMatching() {
        let store = FakePreferencesStore()
        try! store.set(.bool(true), forKey: "k", inDomain: "d")
        let desired = [StateEntry(domain: "d", key: "k", value: .bool(true))]
        let result = computeDrift(desired: desired, store: store,
                                  watchedDomains: [], noise: NoiseFilter(patterns: []))
        XCTAssertTrue(result.drifted.isEmpty)
    }

    func testUntrackedInWatchedDomain() {
        let store = FakePreferencesStore()
        try! store.set(.bool(true), forKey: "Tracked", inDomain: "d")
        try! store.set(.int(9), forKey: "Untracked", inDomain: "d")
        let desired = [StateEntry(domain: "d", key: "Tracked", value: .bool(true))]
        let result = computeDrift(desired: desired, store: store,
                                  watchedDomains: ["d"], noise: NoiseFilter(patterns: []))
        XCTAssertEqual(result.untracked.count, 1)
        XCTAssertEqual(result.untracked[0].line, "NEW    d  Untracked  current=9")
    }

    func testNoiseExcludesUntracked() {
        let store = FakePreferencesStore()
        try! store.set(.int(1), forKey: "Window Frame", inDomain: "d")
        try! store.set(.int(2), forKey: "tilesize", inDomain: "d")
        let result = computeDrift(desired: [], store: store,
                                  watchedDomains: ["d"], noise: NoiseFilter(patterns: ["* Frame"]))
        XCTAssertEqual(result.untracked.map(\.key), ["tilesize"])
    }

    func testUnsupportedCurrentValueIsSkippedNotDrift() {
        let store = FakePreferencesStore()
        store.seed(.unsupported("CFArray"), forKey: "k", inDomain: "d")
        let desired = [StateEntry(domain: "d", key: "k", value: .string("x"))]
        let result = computeDrift(desired: desired, store: store,
                                  watchedDomains: [], noise: NoiseFilter(patterns: []))
        XCTAssertTrue(result.drifted.isEmpty)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertEqual(result.skipped[0].line, "SKIP d k (unsupported type: CFArray)")
    }

    func testUnsupportedUntrackedValueIsSkippedNotNew() {
        let store = FakePreferencesStore()
        store.seed(.unsupported("CFDictionary"), forKey: "k", inDomain: "d")
        let result = computeDrift(desired: [], store: store,
                                  watchedDomains: ["d"], noise: NoiseFilter(patterns: []))
        XCTAssertTrue(result.untracked.isEmpty)
        XCTAssertEqual(result.skipped.count, 1)
    }

    func testEmptyWatchedMeansNoUntrackedScan() {
        let store = FakePreferencesStore()
        try! store.set(.int(1), forKey: "x", inDomain: "d")
        let result = computeDrift(desired: [], store: store,
                                  watchedDomains: [], noise: NoiseFilter(patterns: []))
        XCTAssertTrue(result.untracked.isEmpty)
    }

    func testOutputsSortedByDomainThenKey() {
        let store = FakePreferencesStore()
        try! store.set(.int(1), forKey: "b", inDomain: "z")
        try! store.set(.int(1), forKey: "a", inDomain: "z")
        try! store.set(.int(1), forKey: "a", inDomain: "a")
        let result = computeDrift(desired: [], store: store,
                                  watchedDomains: ["z", "a"], noise: NoiseFilter(patterns: []))
        XCTAssertEqual(result.untracked.map { "\($0.domain)/\($0.key)" }, ["a/a", "z/a", "z/b"])
    }
}
