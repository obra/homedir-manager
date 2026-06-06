import Foundation
import ArgumentParser
import MacosDefaultsCore

struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture",
        abstract: "Emit desired-state lines for a domain (optionally specific keys).")

    @Argument(help: "The CFPreferences domain (or NSGlobalDomain).")
    var domain: String

    @Argument(help: "Specific keys to capture. If omitted, captures the whole domain.")
    var keys: [String] = []

    @Option(name: .long, help: "File listing noise glob patterns (whole-domain capture only).")
    var noise: String?

    func run() throws {
        let noiseFilter: NoiseFilter?
        if let noisePath = noise {
            noiseFilter = NoiseFilter(patterns: parseLineList(try readFileOrExit(noisePath, label: "noise")))
        } else {
            noiseFilter = nil
        }

        let result = captureEntries(domain: domain, keys: keys,
                                    store: CFPreferencesStore(), noise: noiseFilter)
        for skip in result.skips {
            printError(skip.line)
        }
        let output = StateFile.emit(result.entries)
        if !output.isEmpty {
            // emit already adds a trailing newline; write raw to avoid doubling it.
            FileHandle.standardOutput.write(Data(output.utf8))
        }
    }
}
