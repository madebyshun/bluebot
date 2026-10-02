import Foundation
import PrivySDK

// MARK: - Blue Agent session
//
// How BlueBot does everything Blue Chat does, natively, without ever holding a
// key:
//   1. Sign in with email (Privy, the app Blue Chat uses) → the trader's own
//      embedded wallet, the same one they have on Blue Chat.
//   2. That wallet signs Blue Agent's SIWE message (personal_sign, no popup)
//      → POST /api/auth/session {embedded:true} → a 30-day session token,
//      sent as `x-blue-session` on every Blue Agent call. Credits are spent
//      from the wallet that proved itself — exactly as on the web.
//   3. Trades are signed by the same wallet through Privy (eth_sendTransaction
//      on Base 8453). The key stays in Privy's enclave; BlueBot only asks.

@MainActor
final class BlueAgentSession: ObservableObject {
    static let shared = BlueAgentSession()

    enum Phase: Equatable {
        case unconfigured            // no Privy app client id yet
        case starting
        case signedOut
        case sendingCode
        case awaitingCode(email: String)
        case signingIn
        case signedIn(wallet: String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .starting
    @Published private(set) var credits: Int?
    @Published private(set) var dailyRemaining: Int?

    private var privy: (any Privy)?
    private static let sessionKey = "blueagent-session"
    private static let walletKey = "blueagentSessionWallet"

    var wallet: String? { if case .signedIn(let w) = phase { return w } else { return nil } }
    var isSignedIn: Bool { wallet != nil }
    var token: String? { KeychainStore.shared.get(Self.sessionKey) }

    private init() {}

    // MARK: Start

    func start() {
        guard let client = BlueBotConfig.privyAppClientId else { phase = .unconfigured; return }
        if privy == nil {
            privy = PrivySdk.initialize(config: PrivyConfig(appId: BlueBotConfig.privyAppId, appClientId: client))
        }
        Task { await restore() }
    }

    /// Re-applies a changed app client id (Settings → Advanced).
    func reconfigure() { privy = nil; start() }

    private func restore() async {
        guard let privy else { return }
        let auth = await privy.getAuthState()
        guard case .authenticated(let user) = auth, let w = user.embeddedEthereumWallets.first else {
            KeychainStore.shared.remove(Self.sessionKey); phase = .signedOut; return
        }
        // A Blue Agent session still alive for this wallet → done.
        if token != nil, let who = try? await whoami(), who == w.address.lowercased() {
            phase = .signedIn(wallet: who); await refreshCredits(); return
        }
        // Privy remembers the user but the Blue Agent session lapsed → sign again, silently.
        do { try await openBlueAgentSession(with: w); await refreshCredits() }
        catch { phase = .failed(error.localizedDescription) }
    }

    // MARK: Email sign-in

    func sendCode(to email: String) {
        guard let privy else { phase = .unconfigured; return }
        let e = email.trimmingCharacters(in: .whitespaces)
        phase = .sendingCode
        Task {
            do { try await privy.email.sendCode(to: e); phase = .awaitingCode(email: e) }
            catch { phase = .failed("Could not send the code: \(error.localizedDescription)") }
        }
    }

    func verify(code: String) {
        guard let privy, case .awaitingCode(let email) = phase else { return }
        phase = .signingIn
        Task {
            do {
                let user = try await privy.email.loginWithCode(code.trimmingCharacters(in: .whitespaces), sentTo: email)
                let w: any EmbeddedEthereumWallet
                if let existing = user.embeddedEthereumWallets.first { w = existing }
                else { w = try await user.createEthereumWallet() }
                try await openBlueAgentSession(with: w)
                await refreshCredits()
                SoundEngine.shared.play("love")
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func signOut() {
        Task {
            if let t = token {
                var req = URLRequest(url: URL(string: BlueAgentAPI.base + "/api/auth/session")!)
                req.httpMethod = "DELETE"; req.setValue(t, forHTTPHeaderField: "x-blue-session")
                _ = try? await URLSession.shared.data(for: req)
            }
            KeychainStore.shared.remove(Self.sessionKey)
            UserDefaults.standard.removeObject(forKey: Self.walletKey)
            if let privy, let user = await privy.getUser() { await user.logout() }
            credits = nil; dailyRemaining = nil
            phase = .signedOut
        }
    }

    func resetError() { phase = BlueBotConfig.privyAppClientId == nil ? .unconfigured : .signedOut }

    // MARK: SIWE → Blue Agent session

    private func openBlueAgentSession(with w: any EmbeddedEthereumWallet) async throws {
        phase = .signingIn
        let address = w.address
        let (nd, _) = try await URLSession.shared.data(from: URL(string: BlueAgentAPI.base + "/api/auth/nonce")!)
        guard let nonce = (try JSONSerialization.jsonObject(with: nd) as? [String: Any])?["nonce"] as? String else {
            throw Self.err("Blue Agent sign-in is unavailable right now.")
        }
        let message = Self.siweMessage(domain: Self.domain, address: address, nonce: nonce)
        let signature = try await w.provider.request(.personalSign(message: message, address: address))
        var req = URLRequest(url: URL(string: BlueAgentAPI.base + "/api/auth/session")!, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["address": address, "signature": signature, "nonce": nonce, "embedded": true])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let j = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let t = j["token"] as? String, let wal = j["wallet"] as? String else {
            throw Self.err((j["error"] as? String) ?? "Blue Agent refused the sign-in.")
        }
        KeychainStore.shared.set(Self.sessionKey, value: t)
        UserDefaults.standard.set(wal, forKey: Self.walletKey)
        phase = .signedIn(wallet: wal)
    }

    /// The host BlueBot calls — the server signs against its own Host header.
    static var domain: String { URL(string: BlueAgentAPI.base)?.host.map { h in
        if let p = URL(string: BlueAgentAPI.base)?.port { return "\(h):\(p)" } else { return h } } ?? "app.blueagent.dev" }

    static func siweMessage(domain: String, address: String, nonce: String) -> String {
        SIWE.message(domain: domain, address: address, nonce: nonce)
    }

    private func whoami() async throws -> String? {
        let (data, _) = try await authed("GET", "/api/auth/session")
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return j?["status"] as? String == "active" ? (j?["wallet"] as? String) : nil
    }

    // MARK: Authed calls

    /// A Blue Agent call with this session. A 401 drops the session so the UI asks to sign in again.
    func authed(_ method: String, _ path: String, json: Any? = nil, timeout: TimeInterval = 20) async throws -> (Data, Int) {
        guard let url = URL(string: BlueAgentAPI.base + path) else { throw Self.err("Bad address.") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = token { req.setValue(t, forHTTPHeaderField: "x-blue-session") }
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && isSignedIn && path != "/api/auth/session" {
            KeychainStore.shared.remove(Self.sessionKey)
            Task { await self.restore() }
        }
        return (data, code)
    }

    func refreshCredits() async {
        guard let w = wallet, let (data, code) = try? await authed("GET", "/api/credits/balance/\(w)"), code == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        credits = (j["balance"] as? NSNumber)?.intValue
        dailyRemaining = (j["dailyRemaining"] as? NSNumber)?.intValue
    }

    // MARK: Signing a transaction (Base)

    /// Sends a transaction from the trader's own wallet on Base. Returns the tx hash.
    func sendBaseTransaction(to: String, data: String, value: BigUInt) async throws -> String {
        guard let privy, let user = await privy.getUser(), let w = user.embeddedEthereumWallets.first else {
            throw Self.err("Sign in first.")
        }
        await w.provider.switchChain(chainId: BlueBotConfig.baseChainId, rpcUrl: BlueBotConfig.baseRpc)
        let tx = EthereumRpcRequest.UnsignedEthTransaction(
            from: w.address, to: to, data: data,
            value: .hexadecimalNumber(value.hexString),
            chainId: .int(BlueBotConfig.baseChainId))
        return try await w.provider.request(try .ethSendTransaction(transaction: tx))
    }

    static func err(_ m: String) -> NSError { NSError(domain: "BlueBot", code: 1, userInfo: [NSLocalizedDescriptionKey: m]) }
}
