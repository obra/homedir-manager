import Foundation
import ArgumentParser
import MacosDefaultsCore

/// Write a line to stderr.
func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Read a file's text, or print an error to stderr and exit 2.
func readFileOrExit(_ path: String, label: String) throws -> String {
    do {
        return try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        printError("error: cannot read \(label) file '\(path)': \(error.localizedDescription)")
        throw ExitCode(2)
    }
}

/// Parse a state file from a path, mapping read + parse errors to stderr + exit 2.
func loadStateFileOrExit(_ path: String) throws -> [StateEntry] {
    let text = try readFileOrExit(path, label: "statefile")
    do {
        return try StateFile.parse(text)
    } catch let StateFileError.malformedLine(lineNumber, content, reason) {
        printError("error: \(path):\(lineNumber): malformed line (\(reason)): \(content)")
        throw ExitCode(2)
    }
}
