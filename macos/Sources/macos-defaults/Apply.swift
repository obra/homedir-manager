import Foundation
import ArgumentParser
import MacosDefaultsCore

struct Apply: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Apply a desired-state file to the live preferences.")

    @Argument(help: "Path to the desired-state file.")
    var statefile: String

    @Flag(name: .long, help: "Skip the best-effort UI reload after writing.")
    var noReload = false

    func run() throws {
        let entries = try loadStateFileOrExit(statefile)
        let store = CFPreferencesStore()
        do {
            try applyEntries(entries, store: store)
        } catch let error as PreferencesWriteError {
            printError("error: failed to write \(error.domain) \(error.key)")
            throw ExitCode(1)
        }
        if !noReload {
            reloadUI()
        }
    }
}
