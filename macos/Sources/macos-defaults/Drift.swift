import Foundation
import ArgumentParser
import MacosDefaultsCore

struct DriftCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "drift",
        abstract: "Report drift and untracked keys versus the desired-state file.")

    @Argument(help: "Path to the desired-state file.")
    var statefile: String

    @Option(name: .long, help: "File listing watched domains (one per line).")
    var watched: String?

    @Option(name: .long, help: "File listing noise glob patterns (one per line).")
    var noise: String?

    func run() throws {
        let entries = try loadStateFileOrExit(statefile)

        let watchedDomains: [String]
        if let watchedPath = watched {
            watchedDomains = parseLineList(try readFileOrExit(watchedPath, label: "watched"))
        } else {
            // Default: the set of domains appearing in the statefile (stable order).
            var seen: Set<String> = []
            watchedDomains = entries.map(\.domain).filter { seen.insert($0).inserted }
        }

        let noiseFilter: NoiseFilter
        if let noisePath = noise {
            noiseFilter = NoiseFilter(patterns: parseLineList(try readFileOrExit(noisePath, label: "noise")))
        } else {
            noiseFilter = NoiseFilter(patterns: [])
        }

        let result = computeDrift(desired: entries, store: CFPreferencesStore(),
                                  watchedDomains: watchedDomains, noise: noiseFilter)

        for entry in result.skipped {
            printError(entry.line)
        }
        for entry in result.drifted {
            print(entry.line)
        }
        for entry in result.untracked {
            print(entry.line)
        }

        if !result.drifted.isEmpty || !result.untracked.isEmpty {
            throw ExitCode(1)
        }
    }
}
