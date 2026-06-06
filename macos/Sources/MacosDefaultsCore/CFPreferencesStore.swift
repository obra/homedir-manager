import Foundation
import CoreFoundation

/// Classify an in-memory CoreFoundation value into a PrefValue.
/// Pure — inspects type ids only, never the preferences system.
public func classifyCFValue(_ value: CFTypeRef) -> PrefValue {
    let typeID = CFGetTypeID(value)
    if typeID == CFBooleanGetTypeID() {
        return .bool(CFBooleanGetValue((value as! CFBoolean)))
    }
    if typeID == CFNumberGetTypeID() {
        let number = value as! CFNumber
        if CFNumberIsFloatType(number) {
            return .double((value as! NSNumber).doubleValue)
        }
        return .int((value as! NSNumber).intValue)
    }
    if typeID == CFStringGetTypeID() {
        return .string(value as! String)
    }
    let name = CFCopyTypeIDDescription(typeID) as String? ?? "unknown"
    return .unsupported(name)
}

/// Real store backed by the CFPreferences API. NSGlobalDomain maps to kCFPreferencesAnyApplication.
public struct CFPreferencesStore: PreferencesStore {
    public init() {}

    private func applicationID(_ domain: String) -> CFString {
        domain == "NSGlobalDomain" ? kCFPreferencesAnyApplication : (domain as CFString)
    }

    public func keys(inDomain domain: String) -> [String] {
        let appID = applicationID(domain)
        guard let list = CFPreferencesCopyKeyList(
            appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]
        else { return [] }
        return list
    }

    public func value(forKey key: String, inDomain domain: String) -> PrefValue? {
        guard let value = CFPreferencesCopyAppValue(key as CFString, applicationID(domain)) else {
            return nil
        }
        return classifyCFValue(value)
    }

    public func set(_ value: PrefValue, forKey key: String, inDomain domain: String) throws {
        let cfValue: CFPropertyList
        switch value {
        case .bool(let b): cfValue = (b ? kCFBooleanTrue : kCFBooleanFalse)!
        case .int(let i): cfValue = NSNumber(value: i)
        case .double(let d): cfValue = NSNumber(value: d)
        case .string(let s): cfValue = s as CFString
        case .unsupported:
            throw PreferencesWriteError(domain: domain, key: key)
        }
        CFPreferencesSetAppValue(key as CFString, cfValue, applicationID(domain))
    }

    public func synchronize(domain: String) {
        CFPreferencesAppSynchronize(applicationID(domain))
    }
}
