import Foundation

// MARK: - Blue Agent's pre-trade check
//
// POST /api/pretrade-check (public): PASS, WARN or BLOCK for a token, with the
// reasons. The verdict is decided in Blue Agent's code from measured data, not
// by a model. BlueBot only shows it — it does not trade.

struct PreTradeVerdict: Equatable {
    let verdict: String            // PASS · WARN · BLOCK
    let label: String
    let reasons: [(level: String, text: String)]
    var address: String = ""
    /// The address is a pool or a wallet, not a token (code NOT_A_TOKEN).
    var notAToken = false
    /// A pool's two tokens, read from the pool by Blue Agent.
    var poolTokens: [(symbol: String, address: String)] = []
    static func == (a: PreTradeVerdict, b: PreTradeVerdict) -> Bool { a.verdict == b.verdict && a.label == b.label && a.reasons.map(\.text) == b.reasons.map(\.text) }

    struct Failed: LocalizedError { let errorDescription: String? }

    static func run(chain: String, token: String) async throws -> PreTradeVerdict {
        let (data, code) = try await BlueAgentAPI.open("POST", "/api/pretrade-check", json: ["chain": chain, "kind": "swap", "token": token])
        guard code == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any], let v = j["verdict"] as? String else {
            throw Failed(errorDescription: code == 429 ? "The check is busy. Try again in a moment." : "The pre-trade check did not run.")
        }
        let reasons = (j["reasons"] as? [[String: Any]] ?? []).map { (level: ($0["level"] as? String) ?? "INFO", text: ($0["text"] as? String) ?? "") }
        let codes = (j["reasons"] as? [[String: Any]] ?? []).compactMap { $0["code"] as? String }
        let pool = (j["pool"] as? [String: Any]).map { p in ["token0", "token1"].compactMap { k -> (symbol: String, address: String)? in
            guard let t = p[k] as? [String: Any], let a = t["address"] as? String else { return nil }
            let s = (t["symbol"] as? String) ?? ""
            return (symbol: s.isEmpty ? "\(a.prefix(6))…\(a.suffix(4))" : s, address: a)
        } } ?? []
        return PreTradeVerdict(verdict: v, label: (j["label"] as? String) ?? token, reasons: reasons,
                               address: token.lowercased(), notAToken: codes.contains("NOT_A_TOKEN"), poolTokens: pool)
    }
}
