import Foundation

// MARK: - BlueBot configuration

enum BlueBotConfig {
    /// Blue Agent's Privy app — the same one Blue Chat uses, so a trader who
    /// signs in with email here gets the SAME embedded wallet. Public
    /// identifier (it ships in Blue Chat's browser bundle).
    static let privyAppId = "cmt2q0udb001u0chz9apf316b"

    /// The Privy "app client" for this native app (Privy dashboard → App
    /// settings → Clients, allowed bundle id dev.blueagent.bluebot). Read from
    /// UserDefaults first so it can be set without a rebuild:
    ///   defaults write dev.blueagent.bluebot privyAppClientId client-…
    static var privyAppClientId: String? {
        let ud = UserDefaults.standard.string(forKey: "privyAppClientId")?.trimmingCharacters(in: .whitespaces)
        if let ud, !ud.isEmpty { return ud }
        let plist = Bundle.main.object(forInfoDictionaryKey: "PrivyAppClientId") as? String
        return (plist?.isEmpty == false) ? plist : nil
    }

    static let baseChainId = 8453
    static let baseRpc = "https://mainnet.base.org"
    static let baseExplorer = "https://basescan.org"
}

// MARK: - Big unsigned integers (base units of a token)

/// Minimal arbitrary-precision unsigned integer, enough for token amounts:
/// parse/format decimal strings and hex, compare, nothing else.
struct BigUInt: Equatable, Comparable, Sendable {
    /// Little-endian base-2^32 limbs, no trailing zeros (zero = []).
    private(set) var limbs: [UInt32]

    static let zero = BigUInt(limbs: [])
    init(limbs: [UInt32]) { var l = limbs; while l.last == 0 { l.removeLast() }; self.limbs = l }
    init(_ v: UInt64) { self.init(limbs: [UInt32(v & 0xffff_ffff), UInt32(v >> 32)]) }

    var isZero: Bool { limbs.isEmpty }

    private mutating func mulAdd(_ m: UInt32, _ a: UInt32) {
        var carry = UInt64(a)
        for i in limbs.indices {
            let v = UInt64(limbs[i]) * UInt64(m) + carry
            limbs[i] = UInt32(v & 0xffff_ffff); carry = v >> 32
        }
        if carry > 0 { limbs.append(UInt32(carry)) }
    }

    /// Divides in place by a small number, returns the remainder.
    private mutating func divSmall(_ d: UInt32) -> UInt32 {
        var rem: UInt64 = 0
        for i in limbs.indices.reversed() {
            let cur = (rem << 32) | UInt64(limbs[i])
            limbs[i] = UInt32(cur / UInt64(d)); rem = cur % UInt64(d)
        }
        while limbs.last == 0 { limbs.removeLast() }
        return UInt32(rem)
    }

    func multiplied(by m: UInt32) -> BigUInt { var v = self; v.mulAdd(m, 0); return BigUInt(limbs: v.limbs) }
    func divided(by d: UInt32) -> BigUInt { var v = self; _ = v.divSmall(d); return v }
    /// self − other, or nil if that would be negative.
    func minus(_ o: BigUInt) -> BigUInt? {
        if self < o { return nil }
        var out = limbs; var borrow: Int64 = 0
        for i in out.indices {
            var d = Int64(out[i]) - borrow - (i < o.limbs.count ? Int64(o.limbs[i]) : 0)
            borrow = d < 0 ? 1 : 0; if d < 0 { d += 1 << 32 }
            out[i] = UInt32(d)
        }
        return BigUInt(limbs: out)
    }

    init?(decimal s: String) {
        guard !s.isEmpty, s.allSatisfy(\.isNumber) else { return nil }
        var v = BigUInt.zero
        for ch in s { v.mulAdd(10, UInt32(ch.wholeNumberValue!)) }
        self = v
    }

    init?(hex s: String) {
        var h = s.lowercased()
        if h.hasPrefix("0x") { h.removeFirst(2) }
        guard h.allSatisfy(\.isHexDigit) else { return nil }
        var v = BigUInt.zero
        for ch in h { v.mulAdd(16, UInt32(ch.hexDigitValue!)) }
        self = v
    }

    var decimalString: String {
        if isZero { return "0" }
        var v = self; var out: [Character] = []
        while !v.isZero { out.append(Character(String(v.divSmall(10)))) }
        return String(out.reversed())
    }

    var hexString: String {
        if isZero { return "0x0" }
        var s = limbs.reversed().map { String($0, radix: 16) }
        for i in 1..<s.count { s[i] = String(repeating: "0", count: 8 - s[i].count) + s[i] }
        return "0x" + s.joined()
    }

    /// 32-byte big-endian ABI word, no 0x.
    var abiWord: String {
        let h = String(hexString.dropFirst(2))
        return String(repeating: "0", count: max(0, 64 - h.count)) + h
    }

    static func < (a: BigUInt, b: BigUInt) -> Bool {
        if a.limbs.count != b.limbs.count { return a.limbs.count < b.limbs.count }
        for i in a.limbs.indices.reversed() where a.limbs[i] != b.limbs[i] { return a.limbs[i] < b.limbs[i] }
        return false
    }
}

enum Units {
    /// "12.5" with 6 decimals → 12500000. nil for anything not a plain positive decimal.
    static func parse(_ amount: String, decimals: Int) -> BigUInt? {
        let s = amount.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = parts.first else { return nil }
        let frac = parts.count == 2 ? String(parts[1]) : ""
        guard frac.count <= decimals, (whole + frac).allSatisfy(\.isNumber), !(whole + frac).isEmpty else { return nil }
        let digits = String(whole) + frac + String(repeating: "0", count: decimals - frac.count)
        let trimmed = String(digits.drop(while: { $0 == "0" }))
        return trimmed.isEmpty ? .zero : BigUInt(decimal: trimmed)
    }

    /// 12500000 with 6 decimals → "12.5" (at most `maxFrac` fraction digits).
    static func format(_ v: BigUInt, decimals: Int, maxFrac: Int = 6) -> String {
        var d = v.decimalString
        if decimals == 0 { return d }
        if d.count <= decimals { d = String(repeating: "0", count: decimals - d.count + 1) + d }
        let whole = d.dropLast(decimals)
        var frac = String(d.suffix(decimals).prefix(maxFrac))
        while frac.hasSuffix("0") { frac.removeLast() }
        return frac.isEmpty ? String(whole) : "\(whole).\(frac)"
    }
}

// MARK: - ABI + Base RPC

enum ABI {
    static func address(_ a: String) -> String {
        let h = a.lowercased().replacingOccurrences(of: "0x", with: "")
        return String(repeating: "0", count: 64 - h.count) + h
    }
    static func approve(spender: String, amount: BigUInt) -> String { "0x095ea7b3" + address(spender) + amount.abiWord }
    static func balanceOf(_ owner: String) -> String { "0x70a08231" + address(owner) }
    static let decimals = "0x313ce567"
    static let symbol = "0x95d89b41"
}

enum BaseRPC {
    static let native = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
    static func isNative(_ a: String) -> Bool { a.lowercased() == native.lowercased() || a.uppercased() == "ETH" }

    static func call(_ method: String, _ params: [Any]) async throws -> Any {
        var req = URLRequest(url: URL(string: BlueBotConfig.baseRpc)!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        let (data, _) = try await URLSession.shared.data(for: req)
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let e = j?["error"] as? [String: Any] { throw NSError(domain: "rpc", code: 1, userInfo: [NSLocalizedDescriptionKey: (e["message"] as? String) ?? "RPC error"]) }
        return j?["result"] ?? NSNull()
    }

    static func ethCall(to: String, data: String) async throws -> String {
        (try await call("eth_call", [["to": to, "data": data], "latest"]) as? String) ?? "0x"
    }

    static func decimals(of token: String) async throws -> Int {
        if isNative(token) { return 18 }
        let r = try await ethCall(to: token, data: ABI.decimals)
        guard let v = BigUInt(hex: r), let n = Int(v.decimalString), n <= 36 else { throw NSError(domain: "rpc", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not read token decimals."]) }
        return n
    }

    static func balance(of token: String, owner: String) async throws -> BigUInt {
        if isNative(token) {
            return BigUInt(hex: (try await call("eth_getBalance", [owner, "latest"]) as? String) ?? "0x0") ?? .zero
        }
        return BigUInt(hex: try await ethCall(to: token, data: ABI.balanceOf(owner))) ?? .zero
    }

    /// nil while pending; true/false once mined.
    static func receiptStatus(_ hash: String) async throws -> Bool? {
        guard let r = try await call("eth_getTransactionReceipt", [hash]) as? [String: Any] else { return nil }
        return (r["status"] as? String) == "0x1"
    }

    static func waitForReceipt(_ hash: String, timeout: TimeInterval = 120) async throws -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let s = try? await receiptStatus(hash) { return s }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw NSError(domain: "rpc", code: 3, userInfo: [NSLocalizedDescriptionKey: "Still waiting for the transaction to be mined. Check it on Basescan."])
    }
}

// MARK: - Blue Agent SIWE message

enum SIWE {
    /// Byte-for-byte apps/web src/lib/siwe-session-message.ts — the server
    /// rebuilds this exact string from its own Host header and verifies the
    /// signature against it. One character of drift = "Signature does not match".
    static func message(domain: String, address: String, nonce: String) -> String {
        [
            "\(domain) wants you to sign in with your Ethereum account:",
            address.lowercased(),
            "",
            "Sign in to Blue Agent with this wallet for 30 days.",
            "",
            "While signed in, Blue Agent may spend this wallet's prepaid credits on",
            "chat and tool runs, run its scheduled tasks, manage its alerts, and sync",
            "its Blue Chat workspace across devices.",
            "",
            "This signature proves you control this wallet. It does NOT approve a",
            "transaction, move any funds on-chain, or grant any token allowance.",
            "",
            "URI: https://\(domain)",
            "Version: 1",
            "Chain ID: 8453",
            "Nonce: \(nonce)",
        ].joined(separator: "\n")
    }
}
