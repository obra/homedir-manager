/// Apply desired-state entries to the store, then synchronize each touched domain.
/// Fails fast on the first write error (per spec §9: a failing write signals a recurring problem).
public func applyEntries(_ entries: [StateEntry], store: PreferencesStore) throws {
    var touchedDomains: Set<String> = []
    for entry in entries {
        try store.set(entry.value, forKey: entry.key, inDomain: entry.domain)
        touchedDomains.insert(entry.domain)
    }
    for domain in touchedDomains {
        store.synchronize(domain: domain)
    }
}
