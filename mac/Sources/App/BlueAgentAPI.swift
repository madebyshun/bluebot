import Foundation

// MARK: - Blue Agent API
//
// BlueBot runs on Blue Agent's API, linked to the wallet you already use on
// blueagent.dev — no new wallet, no key (apps/web, lib/devices.ts):
//
//   POST /api/devices/code   {name, kind:"mac"} → user_code to show, device_code to poll with
//   POST /api/devices/token  {device_code}      → authorization_pending … then access_token, once
//   GET  /api/devices/me     Bearer bbt_…       → wallet, scopes, today's chat cap
//   GET  /api/devices/feed   Bearer             → the wallet's timeline
//   POST /api/devices/chat   Bearer (chat)      → Blue Agent chat as SSE, on the wallet's credits
//   *    /api/watches        Bearer (read / alerts) → price alerts
//   POST /api/devices/revoke Bearer             → unlink this Mac
// Public, no token: /api/base-tokens, /api/hood/snapshot, /api/pretrade-check,
// /api/credits/balance/<wallet>.
//
// What the link may do is chosen by the wallet's owner when approving it on
// app.blueagent.dev/link: it always reads; it chats only with `chat` (on the
// wallet's credits, as many as it holds) and edits alerts only with `alerts`. It can never
// sign or move funds.
//
// The token lives in the Keychain (KeychainStore, service dev.blueagent.bluebot).
// `apiBase` in UserDefaults overrides the server for local development:
//   defaults write dev.blueagent.bluebot apiBase http://localhost:3000

enum BlueAgentAPI {
    static let tokenKey = "blueagent-device-token"
    static let defaultBase = "https://app.blueagent.dev"
    /// Buying credits needs the wallet to sign, so it happens on the web.
    static let topUpURL = "https://app.blueagent.dev/plans"

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

    struct Me: Decodable, Sendable, Equatable {
        let wallet: String
        let scopes: [String]
        var canChat: Bool { scopes.contains("chat") }
        var canEditAlerts: Bool { scopes.contains("alerts") }
    }

    struct Feed: Decodable, Sendable {
        let wallet: String
        let items: [FeedItem]
        let unavailable: [String]?
        let next_poll_s: Int?

        /// Item by item: one entry of a shape this build does not know is
        /// skipped, instead of failing the whole feed.
        private struct Lenient: Decodable { let item: FeedItem?; init(from d: Decoder) throws { item = try? FeedItem(from: d) } }
        enum CodingKeys: String, CodingKey { case wallet, items, unavailable, next_poll_s }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            wallet = (try? c.decode(String.self, forKey: .wallet)) ?? ""
            items = ((try? c.decode([Lenient].self, forKey: .items)) ?? []).compactMap(\.item)
            unavailable = try? c.decode([String].self, forKey: .unavailable)
            next_poll_s = try? c.decode(Int.self, forKey: .next_poll_s)
        }
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
        catch { throw Failure.server(code, "Unexpected answer from Blue Agent (\(error.localizedDescription)).") }
    }

    static func me() async throws -> Me {
        guard let t = token else { throw Failure.unlinked }
        let (data, code) = try await raw("GET", "/api/devices/me", body: nil, bearer: t)
        if code == 401 { throw Failure.unlinked }
        guard code == 200 else { throw Failure.server(code, message(data)) }
        do { return try JSONDecoder().decode(Me.self, from: data) }
        catch { throw Failure.server(code, "Unexpected answer from Blue Agent.") }
    }

    /// Any call as this linked Mac (Bearer), with a JSON body of any shape.
    /// The body is serialised here, on the caller's actor, so only `Data`
    /// crosses into the network call.
    @MainActor
    static func authed(_ method: String, _ path: String, json: Any? = nil, timeout: TimeInterval = 20) async throws -> (Data, Int) {
        guard let t = token else { throw Failure.unlinked }
        return try await request(method, path, body: encode(json), bearer: t, timeout: timeout)
    }

    /// A public call (no token).
    @MainActor
    static func open(_ method: String, _ path: String, json: Any? = nil) async throws -> (Data, Int) {
        try await request(method, path, body: encode(json), bearer: nil, timeout: 20)
    }

    private static func encode(_ json: Any?) -> Data? { json.flatMap { try? JSONSerialization.data(withJSONObject: $0) } }

    /// (credits, daily free left) for a wallet — public on Blue Agent.
    static func credits(wallet: String) async -> (Int?, Int?) {
        guard let (data, code) = try? await open("GET", "/api/credits/balance/\(wallet)"), code == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }
        return ((j["balance"] as? NSNumber)?.intValue, (j["dailyRemaining"] as? NSNumber)?.intValue)
    }

    static func errorMessage(_ data: Data) -> String { message(data) }

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
        try await request(method, path, body: encode(body), bearer: bearer, timeout: 15)
    }

    private static func request(_ method: String, _ path: String, body: Data?, bearer: String?, timeout: TimeInterval) async throws -> (Data, Int) {
        guard let url = URL(string: base + path) else { throw Failure.network("bad server address") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
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
