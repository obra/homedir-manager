/// A key omitted from capture output, with the reason rendered for stderr.
public struct CaptureSkip: Equatable {
    public enum Reason: Equatable {
        case unsupportedType(String)       // CF type name
        case stringHasTabOrNewline
    }
    public let domain: String
    public let key: String
    public let reason: Reason

    public var line: String {
        switch reason {
        case .unsupportedType(let name):
            return "SKIP \(domain) \(key) (unsupported type: \(name))"
        case .stringHasTabOrNewline:
            return "SKIP \(domain) \(key) (unsupported: string contains TAB or newline)"
        }
    }
}

public struct CaptureResult: Equatable {
    public let entries: [StateEntry]
    public let skips: [CaptureSkip]
}

/// Build desired-state entries for a domain.
/// With explicit `keys`, capture just those (a missing key yields nothing). With no keys,
/// capture every key in the domain minus those matched by `noise` (if provided).
/// Unsupported types and TAB/newline strings are skipped, never emitted. Entries are sorted.
public func captureEntries(
    domain: String,
    keys: [String],
    store: PreferencesStore,
    noise: NoiseFilter?
) -> CaptureResult {
    let targetKeys: [String]
    if keys.isEmpty {
        targetKeys = store.keys(inDomain: domain).filter { key in
            !(noise?.matches(key) ?? false)
        }
    } else {
        targetKeys = keys
    }

    var entries: [StateEntry] = []
    var skips: [CaptureSkip] = []
    for key in targetKeys {
        guard let value = store.value(forKey: key, inDomain: domain) else { continue }
        switch value {
        case .unsupported(let name):
            skips.append(CaptureSkip(domain: domain, key: key, reason: .unsupportedType(name)))
        case .string(let s) where s.contains("\t") || s.contains("\n"):
            skips.append(CaptureSkip(domain: domain, key: key, reason: .stringHasTabOrNewline))
        default:
            entries.append(StateEntry(domain: domain, key: key, value: value))
        }
    }

    entries.sort { ($0.domain, $0.key) < ($1.domain, $1.key) }
    skips.sort { ($0.domain, $0.key) < ($1.domain, $1.key) }
    return CaptureResult(entries: entries, skips: skips)
}
