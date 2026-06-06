import XCTest
import Foundation
import CoreFoundation

final class CLITests: XCTestCase {
    let itestDomain = "com.macos-defaults.itest"

    override func tearDown() {
        super.tearDown()
        // Remove every key we may have written to the throwaway domain.
        let appID = itestDomain as CFString
        if let keys = CFPreferencesCopyKeyList(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            as? [String] {
            for key in keys {
                CFPreferencesSetAppValue(key as CFString, nil, appID)
            }
        }
        CFPreferencesAppSynchronize(appID)
    }

    /// Directory containing the built `macos-defaults` binary.
    var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("couldn't locate the products directory")
    }

    @discardableResult
    func run(_ args: [String]) -> (out: String, err: String, code: Int32) {
        let process = Process()
        process.executableURL = productsDirectory.appendingPathComponent("macos-defaults")
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try! process.run()
        process.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (out, err, process.terminationStatus)
    }

    func tempFile(_ contents: String) -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-test-\(UUID().uuidString)")
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func testVersion() {
        let r = run(["--version"])
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.contains("0.1.0"), "got: \(r.out)")
    }

    func testHelpListsSubcommands() {
        let r = run(["--help"])
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.contains("apply"))
        XCTAssertTrue(r.out.contains("drift"))
        XCTAssertTrue(r.out.contains("capture"))
    }

    func testMalformedStatefileExits2WithLineNumber() {
        let path = tempFile("good\tk\tbool\ttrue\nbad-line-without-tabs")
        let r = run(["drift", path])
        XCTAssertEqual(r.code, 2)
        XCTAssertTrue(r.err.contains(":2:"), "stderr: \(r.err)")
        XCTAssertEqual(r.out, "")
    }

    func testMissingStatefileExits2() {
        let r = run(["apply", "/no/such/file/here.tsv"])
        XCTAssertEqual(r.code, 2)
        XCTAssertTrue(r.err.lowercased().contains("cannot read"))
    }

    func testApplyThenDriftCleanRoundTrip() {
        let statefile = tempFile("\(itestDomain)\tGreeting\tstring\thello\n")
        let applyResult = run(["apply", statefile, "--no-reload"])
        XCTAssertEqual(applyResult.code, 0, "apply stderr: \(applyResult.err)")

        // drift against the same statefile should now be clean (exit 0, no output).
        let driftResult = run(["drift", statefile])
        XCTAssertEqual(driftResult.code, 0, "drift stdout: \(driftResult.out) stderr: \(driftResult.err)")
        XCTAssertEqual(driftResult.out, "")
    }

    func testDriftReportsExit1() {
        // Apply a known value, then drift against a statefile wanting a different value.
        let setup = tempFile("\(itestDomain)\tTileSize\tint\t36\n")
        XCTAssertEqual(run(["apply", setup, "--no-reload"]).code, 0)

        let desired = tempFile("\(itestDomain)\tTileSize\tint\t48\n")
        let r = run(["drift", desired])
        XCTAssertEqual(r.code, 1)
        XCTAssertTrue(r.out.contains("DRIFT"))
        XCTAssertTrue(r.out.contains("current=36"))
        XCTAssertTrue(r.out.contains("desired=48"))
    }

    func testCaptureExplicitKey() {
        let setup = tempFile("\(itestDomain)\tColor\tstring\tblue\n")
        XCTAssertEqual(run(["apply", setup, "--no-reload"]).code, 0)

        let r = run(["capture", itestDomain, "Color"])
        XCTAssertEqual(r.code, 0)
        XCTAssertEqual(r.out, "\(itestDomain)\tColor\tstring\tblue\n")
    }

    func testCaptureUnknownDomainIsEmptyExit0() {
        let r = run(["capture", "com.macos-defaults.does-not-exist"])
        XCTAssertEqual(r.code, 0)
        XCTAssertEqual(r.out, "")
    }
}
