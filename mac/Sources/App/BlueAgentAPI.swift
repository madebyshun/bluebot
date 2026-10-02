import Foundation

// MARK: - Blue Agent API
//
// BlueBot runs on Blue Agent's device API (apps/web, lib/devices.ts):
//
//   POST /api/devices/code   {name, kind:"mac"} → user_code to show, device_code to poll with
//   POST /api/devices/token  {device_code}      → authorization_pending … then access_token, once
//   GET  /api/devices/feed   Bearer bbt_…       → the wallet's timeline (alerts, trades, checks, blocks)
//   POST /api/devices/revoke Bearer bbt_…       → unlink this Mac
//
// The token is READ-ONLY: it shows activity and nothing else. It is not a Blue
// Agent session, so it cannot spend credits, arm alerts, chat or prepare a
// trade. A fired automation opens its trade card on the web (`open_url`),
// where the wallet signs. BlueBot never holds a key.
//
// The token lives in the Keychain (KeychainStore, service dev.blueagent.bluebot).
// `apiBase` in UserDefaults overrides the server for local development:
//   defaults write dev.blueagent.bluebot apiBase http://localhost:3000

enum BlueAgentAPI {
    static let tokenKey = "blueagent-device-token"
    static let defaultBase = "https://app.blueagent.dev"

    static var base: String {
        let v = UserDefaults.standard.string(forKey: "apiBase")?.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? defaultBase : (v.hasSuffix("/") ? String(v.dropLast()) : v)
    }

    static var token: String? { KeychainStore.shared.get(tokenKey) }

    struct CodeResponse: Decodable, Sendable {
        let user_code: String
        let device_code: String
        let verification_uri_complete: String
        let expires_in: Int
        let interval: Int
    }

    struct DeviceInfo: Decodable, Sendable { let id: String; let name: String }

    struct TokenResponse: Decodable, Sendable {
        let access_token: String
        let device: DeviceInfo
        let feed_poll_s: Int?
    }

    struct FeedItem: Decodable, Equatable, Sendable, Identifiable {
        let id: String
        let at: Double
        let kind: String          // alert · trade · automation_checked · task_run · task_failed · blocked
        let title: String
        let detail: String?
        let chain: String?        // base · robinhood
        let href: String?         // explorer link for a signed trade
        let open_url: String?     // a fired alert: the trade card / alerts chat on the web
    }

    struct Feed: Decodable, Sendable {
        let wallet: String
        let items: [FeedItem]
        let unavailable: [String]?
        let next_poll_s: Int?
    }

    enum Failure: Error, LocalizedError {
        case unlinked
        case expired
        case server(Int, String)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .unlinked: return "This Mac is not linked to a wallet."
            case .expired: return "The code expired. Get a new one."
            case .server(let code, let msg): return msg.isEmpty ? "Blue Agent answered \(code)." : msg
            case .network(let msg): return "Could not reach Blue Agent: \(msg)"
            }
        }
    }

    // MARK: Calls

    static func requestCode(name: String) async throws -> CodeResponse {
        try await send("POST", "/api/devices/code", body: ["name": name, "kind": "mac"], as: CodeResponse.self)
    }

    /// nil while the person has not approved yet.
    static func pollToken(deviceCode: String) async throws -> TokenResponse? {
        let (data, code) = try await raw("POST", "/api/devices/token", body: ["device_code": deviceCode], bearer: nil)
        if code == 200 { return try JSONDecoder().decode(TokenResponse.self, from: data) }
        let err = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? ""
        if err == "authorization_pending" || err == "slow_down" { return nil }
        if err == "expired_token" { throw Failure.expired }
        throw Failure.server(code, err)
    }

    static func feed() async throws -> Feed {
        guard let t = token else { throw Failure.unlinked }
        let (data, code) = try await raw("GET", "/api/devices/feed", body: nil, bearer: t)
        if code == 401 { throw Failure.unlinked }
        guard code == 200 else { throw Failure.server(code, message(data)) }
        do { return try JSONDecoder().decode(Feed.self, from: data) }
        catch { throw Failure.server(code, "Unexpected answer from Blue Agent.") }
    }

    /// Unlinks this Mac on the server, then forgets the token either way.
    static func unlink() async {
        if let t = token { _ = try? await raw("POST", "/api/devices/revoke", body: [:], bearer: t) }
        KeychainStore.shared.remove(tokenKey)
    }

    // MARK: Plumbing

    private static func send<T: Decodable>(_ method: String, _ path: String, body: [String: String], as: T.Type) async throws -> T {
        let (data, code) = try await raw(method, path, body: body, bearer: nil)
        guard code == 200 else { throw Failure.server(code, message(data)) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func raw(_ method: String, _ path: String, body: [String: String]?, bearer: String?) async throws -> (Data, Int) {
        guard let url = URL(string: base + path) else { throw Failure.network("bad server address") }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
    }

    private static func message(_ data: Data) -> String {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? ""
    }
}
