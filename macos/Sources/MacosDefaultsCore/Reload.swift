import Foundation

/// UI agents killed (best-effort) after `apply` so settings are picked up.
public let defaultReloadAgents = ["Dock", "Finder", "SystemUIServer"]

/// Best-effort `killall` of an agent; failures (e.g. not running) are ignored.
public func killallAgent(_ name: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = [name]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}

/// Reload UI agents. `run` is injectable so tests never actually kill processes.
public func reloadUI(agents: [String] = defaultReloadAgents, run: (String) -> Void = killallAgent) {
    for agent in agents {
        run(agent)
    }
}
