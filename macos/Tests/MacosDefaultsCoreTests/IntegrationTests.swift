import XCTest
import Foundation
import CoreFoundation
@testable import MacosDefaultsCore

final class IntegrationTests: XCTestCase {
    let domain = "com.macos-defaults.itest"

    override func tearDown() {
        super.tearDown()
        let appID = domain as CFString
        if let keys = CFPreferencesCopyKeyList(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            as? [String] {
            for key in keys {
                CFPreferencesSetAppValue(key as CFString, nil, appID)
            }
        }
        CFPreferencesAppSynchronize(appID)
    }

    func testRealRoundTripAllScalarTypes() throws {
        let store = CFPreferencesStore()
        try store.set(.bool(true), forKey: "Flag", inDomain: domain)
        try store.set(.int(48), forKey: "Size", inDomain: domain)
        try store.set(.double(1.5), forKey: "Delay", inDomain: domain)
        try store.set(.string("hello world"), forKey: "Name", inDomain: domain)
        store.synchronize(domain: domain)

        XCTAssertEqual(store.value(forKey: "Flag", inDomain: domain), .bool(true))
        XCTAssertEqual(store.value(forKey: "Size", inDomain: domain), .int(48))
        XCTAssertEqual(store.value(forKey: "Delay", inDomain: domain), .double(1.5))
        XCTAssertEqual(store.value(forKey: "Name", inDomain: domain), .string("hello world"))

        let keys = Set(store.keys(inDomain: domain))
        XCTAssertTrue(keys.isSuperset(of: ["Flag", "Size", "Delay", "Name"]))
    }

    func testUnsetKeyReturnsNil() {
        let store = CFPreferencesStore()
        XCTAssertNil(store.value(forKey: "NeverSetKey", inDomain: domain))
    }
}
