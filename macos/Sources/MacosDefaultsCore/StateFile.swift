import Foundation

/// One desired-state entry: a scalar value for a key in a domain.
public struct StateEntry: Equatable {
    public let domain: String
    public let key: String
    public let value: PrefValue
    public init(domain: String, key: String, value: PrefValue) {
        self.domain = domain
        self.key = key
        self.value = value
    }
}

public enum StateFileError: Error, Equatable {
    /// 1-based line number, the offending line's content, and a human reason.
    case malformedLine(lineNumber: Int, content: String, reason: String)
}

public enum StateFile {
    /// Parse desired-state text into entries. Order is preserved (callers sort if needed).
    /// Blank lines and `#` comment lines are ignored. Any malformed line is a hard error.
    public static func parse(_ text: String) throws -> [StateEntry] {
        var entries: [StateEntry] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, raw) in lines.enumerated() {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let lineNumber = index + 1
            let fields = line.components(separatedBy: "\t")
            guard fields.count == 4 else {
                throw StateFileError.malformedLine(
                    lineNumber: lineNumber, content: line,
                    reason: "expected 4 TAB-separated fields, got \(fields.count)")
            }
            let (domain, key, type, value) = (fields[0], fields[1], fields[2], fields[3])
            guard !domain.isEmpty else {
                throw StateFileError.malformedLine(lineNumber: lineNumber, content: line, reason: "empty domain")
            }
            guard !key.isEmpty else {
                throw StateFileError.malformedLine(lineNumber: lineNumber, content: line, reason: "empty key")
            }

            let prefValue: PrefValue
            switch type {
            case "bool":
                switch value {
                case "true": prefValue = .bool(true)
                case "false": prefValue = .bool(false)
                default:
                    throw StateFileError.malformedLine(lineNumber: lineNumber, content: line,
                        reason: "bool value must be true or false")
                }
            case "int":
                guard let i = Int(value) else {
                    throw StateFileError.malformedLine(lineNumber: lineNumber, content: line,
                        reason: "unparsable int value")
                }
                prefValue = .int(i)
            case "float":
                guard let d = Double(value) else {
                    throw StateFileError.malformedLine(lineNumber: lineNumber, content: line,
                        reason: "unparsable float value")
                }
                prefValue = .double(d)
            case "string":
                prefValue = .string(value)
            default:
                throw StateFileError.malformedLine(lineNumber: lineNumber, content: line,
                    reason: "unknown type '\(type)'")
            }
            entries.append(StateEntry(domain: domain, key: key, value: prefValue))
        }
        return entries
    }

    /// Emit entries as TSV, sorted by (domain, key), one trailing newline.
    public static func emit(_ entries: [StateEntry]) -> String {
        let sorted = entries.sorted { ($0.domain, $0.key) < ($1.domain, $1.key) }
        var out = ""
        for e in sorted {
            out += "\(e.domain)\t\(e.key)\t\(e.value.typeToken)\t\(e.value.serialized)\n"
        }
        return out
    }
}
