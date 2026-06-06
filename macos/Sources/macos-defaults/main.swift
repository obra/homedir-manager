import ArgumentParser

struct MacosDefaults: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macos-defaults",
        abstract: "Capture, diff, and apply a curated set of scalar macOS defaults.",
        version: "0.1.0",
        subcommands: [Apply.self, DriftCommand.self, Capture.self])
}

MacosDefaults.main()
