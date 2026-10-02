import Foundation
import Security

// MARK: - Keychain (service dev.blueagent.bluebot)

enum Keychain {
    static let service = "dev.blueagent.bluebot"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        // Delete existing item first (update pattern)
        let lookup: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(lookup as CFDictionary)
        // Add with strictest access control:
        // WhenUnlockedThisDeviceOnly = accessible only while Mac is unlocked,
        // never synced to iCloud, never migrated to another device.
        let item: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Keychain cache
//
// Reads BlueBot's keys ONCE at launch (on the main thread, from AppDelegate);
// every later read comes from memory. Items are this-device-only, never synced.

final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    /// Every key BlueBot keeps. A key missing here is NOT reloaded at launch,
    /// which would sign the trader out on every restart.
    private static let allKeys = [
        "blueagent-session",        // Blue Agent SIWE session (BlueAgentSession)
        "blueagent-device-token",   // watch-only read token (BlueAgentAPI)
    ]

    private init() {
        for key in Self.allKeys { if let v = Keychain.load(key: key) { cache[key] = v } }
    }

    func get(_ key: String) -> String? { lock.withLock { cache[key] } }

    func set(_ key: String, value: String) {
        lock.withLock { cache[key] = value }
        Keychain.save(key: key, value: value)
    }

    func remove(_ key: String) {
        lock.withLock { cache[key] = nil }
        Keychain.delete(key: key)
    }
}
