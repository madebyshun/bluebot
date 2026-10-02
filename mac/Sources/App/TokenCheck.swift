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
    static func == (a: PreTradeVerdict, b: PreTradeVerdict) -> Bool { a.verdict == b.verdict && a.label == b.label && a.reasons.map(\.text) == b.reasons.map(\.text) }

    struct Failed: LocalizedError { let errorDescription: String? }

    static func run(chain: String, token: String) async throws -> PreTradeVerdict {
        let (data, code) = try await BlueAgentAPI.open("POST", "/api/pretrade-check", json: ["chain": chain, "kind": "swap", "token": token])
        guard code == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any], let v = j["verdict"] as? String else {
            throw Failed(errorDescription: code == 429 ? "The check is busy. Try again in a moment." : "The pre-trade check did not run.")
        }
        let reasons = (j["reasons"] as? [[String: Any]] ?? []).map { (level: ($0["level"] as? String) ?? "INFO", text: ($0["text"] as? String) ?? "") }
        return PreTradeVerdict(verdict: v, label: (j["label"] as? String) ?? token, reasons: reasons)
    }
}
