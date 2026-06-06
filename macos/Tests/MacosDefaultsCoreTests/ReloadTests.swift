import XCTest
@testable import MacosDefaultsCore

final class ReloadTests: XCTestCase {
    func testDefaultAgentList() {
        XCTAssertEqual(defaultReloadAgents, ["Dock", "Finder", "SystemUIServer"])
    }

    func testReloadInvokesRunnerForEachAgent() {
        var called: [String] = []
        reloadUI(agents: ["A", "B"]) { called.append($0) }
        XCTAssertEqual(called, ["A", "B"])
    }
}
