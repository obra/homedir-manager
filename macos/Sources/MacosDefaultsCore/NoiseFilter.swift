import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Matches preference key names against fnmatch-style globs (`*`, `?`, classes).
public struct NoiseFilter {
    public let patterns: [String]
    public init(patterns: [String]) {
        self.patterns = patterns
    }

    public func matches(_ key: String) -> Bool {
        for pattern in patterns where fnmatch(pattern, key, 0) == 0 {
            return true
        }
        return false
    }
}

/// Parse a plain-text list file body: one entry per line, `#` comments and blank lines ignored,
/// surrounding whitespace trimmed.
public func parseLineList(_ text: String) -> [String] {
    var result: [String] = []
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = String(raw).trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        result.append(trimmed)
    }
    return result
}
