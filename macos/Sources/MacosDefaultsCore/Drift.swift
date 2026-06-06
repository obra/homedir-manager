/// A desired key whose current effective value differs (or is unset).
public struct DriftEntry: Equatable {
    public let domain: String
    public let key: String
    public let current: PrefValue?  // nil = unset
    public let desired: PrefValue

    public var line: String {
        let cur = current?.serialized ?? "unset"
        return "DRIFT  \(domain)  \(key)  current=\(cur)  desired=\(desired.serialized)"
    }
}

/// A key set in a watched domain that is neither in the desired-state nor matched by noise.
public struct UntrackedEntry: Equatable {
    public let domain: String
    public let key: String
    public let value: PrefValue

    public var line: String {
        "NEW    \(domain)  \(key)  current=\(value.serialized)"
    }
}

/// A key whose current value is an unsupported type — reported, never written/diffed.
public struct SkippedEntry: Equatable {
    public let domain: String
    public let key: String
    public let typeName: String

    public var line: String {
        "SKIP \(domain) \(key) (unsupported type: \(typeName))"
    }
}

public struct DriftResult: Equatable {
    public let drifted: [DriftEntry]
    public let untracked: [UntrackedEntry]
    public let skipped: [SkippedEntry]
}

/// Compute drift and untracked sets. Noise filtering applies only to untracked enumeration.
/// Unsupported current values become `skipped`, never drifted/untracked.
public func computeDrift(
    desired: [StateEntry],
    store: PreferencesStore,
    watchedDomains: [String],
    noise: NoiseFilter
) -> DriftResult {
    var drifted: [DriftEntry] = []
    var untracked: [UntrackedEntry] = []
    var skipped: [SkippedEntry] = []

    // Desired keys, for both the drift pass and to exclude from untracked.
    var desiredKeys: Set<String> = []  // "domain\tkey"
    for entry in desired {
        desiredKeys.insert("\(entry.domain)\t\(entry.key)")
        let current = store.value(forKey: entry.key, inDomain: entry.domain)
        if case .unsupported(let name) = current {
            skipped.append(SkippedEntry(domain: entry.domain, key: entry.key, typeName: name))
            continue
        }
        if current != entry.value {
            drifted.append(DriftEntry(domain: entry.domain, key: entry.key,
                                      current: current, desired: entry.value))
        }
    }

    for domain in watchedDomains {
        for key in store.keys(inDomain: domain) {
            if desiredKeys.contains("\(domain)\t\(key)") { continue }
            if noise.matches(key) { continue }
            guard let value = store.value(forKey: key, inDomain: domain) else { continue }
            if case .unsupported(let name) = value {
                skipped.append(SkippedEntry(domain: domain, key: key, typeName: name))
                continue
            }
            untracked.append(UntrackedEntry(domain: domain, key: key, value: value))
        }
    }

    drifted.sort { ($0.domain, $0.key) < ($1.domain, $1.key) }
    untracked.sort { ($0.domain, $0.key) < ($1.domain, $1.key) }
    skipped.sort { ($0.domain, $0.key) < ($1.domain, $1.key) }
    return DriftResult(drifted: drifted, untracked: untracked, skipped: skipped)
}
