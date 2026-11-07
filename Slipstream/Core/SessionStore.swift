import Foundation
import Security
import LocalAuthentication

struct SessionCookie: Codable, Sendable {
    let value: String
    let expires: Date?
    init?(cookie: HTTPCookie) {
        guard cookie.name == "sails.sid", cookie.isSecure,
              ["floatplane.com", "www.floatplane.com"].contains(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))),
              cookie.expiresDate.map({ $0 > Date() }) ?? true else { return nil }
        value = cookie.value
        expires = cookie.expiresDate
    }
    var isExpired: Bool { expires.map { $0 <= Date() } ?? false }
    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: "sails.sid", .value: value, .domain: "www.floatplane.com", .path: "/", .secure: "TRUE"
        ]
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)
    }
}

enum SessionStore {
    private static var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Bundle.main.object(forInfoDictionaryKey: "SlipstreamKeychainService") as? String ?? "Slipstream.session",
        kSecAttrAccount as String: "floatplane"
    ] }
    static func load(allowUserInteraction: Bool = false) async throws -> SessionCookie? {
        try await Task.detached { try read(allowUserInteraction: allowUserInteraction) }.value
    }
    private static func read(allowUserInteraction: Bool) throws -> SessionCookie? {
        var q = query
        #if os(macOS)
        let authentication = LAContext()
        authentication.interactionNotAllowed = !allowUserInteraction
        q[kSecUseAuthenticationContext as String] = authentication
        #endif
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StoreError(status: status) }
        let cookie = try JSONDecoder().decode(SessionCookie.self, from: data)
        if cookie.isExpired { try remove(); return nil }
        return cookie
    }
    static func save(_ cookie: SessionCookie) async throws {
        try await Task.detached { try write(cookie) }.value
    }
    private static func write(_ cookie: SessionCookie) throws {
        let data = try JSONEncoder().encode(cookie)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw StoreError(status: added) }
        } else if status != errSecSuccess { throw StoreError(status: status) }
    }
    static func delete() async throws {
        try await Task.detached { try remove() }.value
    }
    private static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError(status: status) }
    }
    struct StoreError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Could not access the saved session in Keychain (\(status))." }
    }
}
