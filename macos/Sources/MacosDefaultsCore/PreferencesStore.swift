/// A scalar (or detected-but-unsupported) preference value.
public enum PrefValue: Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case unsupported(String)  // associated value: CoreFoundation type name

    /// State-file type token. `unsupported` has no valid token in the file format.
    public var typeToken: String {
        switch self {
        case .bool: return "bool"
        case .int: return "int"
        case .double: return "float"
        case .string: return "string"
        case .unsupported: return "unsupported"
        }
    }

    /// Serialized scalar text for the value field / output lines.
    public var serialized: String {
        switch self {
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return "\(d)"
        case .string(let s): return s
        case .unsupported(let name): return "<unsupported \(name)>"
        }
    }
}

/// Error thrown by a store when a write fails.
public struct PreferencesWriteError: Error, Equatable {
    public let domain: String
    public let key: String
    public init(domain: String, key: String) {
        self.domain = domain
        self.key = key
    }
}

/// The CFPreferences operations the verbs need. All verb logic depends only on this.
public protocol PreferencesStore {
    func keys(inDomain domain: String) -> [String]
    func value(forKey key: String, inDomain domain: String) -> PrefValue?
    func set(_ value: PrefValue, forKey key: String, inDomain domain: String) throws
    func synchronize(domain: String)
}

/// In-memory store for unit tests. Never touches the system.
public final class FakePreferencesStore: PreferencesStore {
    private var storage: [String: [String: PrefValue]] = [:]
    /// When true, `set` throws `PreferencesWriteError` (to test apply's fail-fast path).
    public var failOnSet = false

    public init() {}

    /// Insert any value, including `.unsupported`, bypassing `set`'s scalar checks.
    public func seed(_ value: PrefValue, forKey key: String, inDomain domain: String) {
        storage[domain, default: [:]][key] = value
    }

    public func keys(inDomain domain: String) -> [String] {
        guard let domainStorage = storage[domain] else { return [] }
        return Array(domainStorage.keys)
    }

    public func value(forKey key: String, inDomain domain: String) -> PrefValue? {
        storage[domain]?[key]
    }

    public func set(_ value: PrefValue, forKey key: String, inDomain domain: String) throws {
        if failOnSet { throw PreferencesWriteError(domain: domain, key: key) }
        storage[domain, default: [:]][key] = value
    }

    public func synchronize(domain: String) {}
}
