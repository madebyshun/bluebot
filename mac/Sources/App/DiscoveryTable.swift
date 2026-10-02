import Foundation

// MARK: - List results from chat tools, as rows
//
// On Blue Chat these tools render a CARD (apps/web DiscoveryCard.tsx,
// `discoveryRows`) and the model's text only points at it ("10 trending
// tokens on Base above…"). BlueBot renders the same rows from the same
// fields, so the answer is never a caption for a table that isn't there.
// Every value is copied from the tool's payload; a missing one is left out,
// never filled in.

struct DiscoveryRow: Equatable, Identifiable {
    let id: String
    let symbol: String
    let chain: String          // Base · Robinhood Chain
    let facts: [String]
    let warning: String?       // honeypot / impersonation, shown in red
}

struct DiscoveryTable: Equatable {
    let title: String
    let rows: [DiscoveryRow]
    let more: Int
    let note: String?

    static let tools: Set<String> = ["hub_safe_trending", "hub_rh_movers", "hub_rh_new_listings", "hub_rh_search", "hub_rh_quote", "hub_rh_index"]

    private static let flagText: [String: String] = [
        "IMPERSONATION_CHECK": "⚠ wears a pinned token's symbol from another contract",
        "TAX_UNVERIFIED": "tax unverified", "HIGH_TAX": "sell tax over 5%", "BLACKLIST_CAPABLE": "has a blacklist function",
        "UNLOCK_OVERHANG": "large unlock overhang", "MICRO_CAP": "micro cap", "DUMPING": "dumping", "CHURN": "high churn", "ARB_FLOW": "arb flow",
    ]

    static func from(tool: String, result r: [String: Any]) -> DiscoveryTable? {
        guard tools.contains(tool), (r["error"] as? String)?.isEmpty ?? true else { return nil }
        func list(_ k: String) -> [[String: Any]] { r[k] as? [[String: Any]] ?? [] }
        func s(_ v: Any?) -> String { v as? String ?? "" }
        func rh(_ x: [String: Any], _ extra: [String] = []) -> DiscoveryRow {
            let t = s(x["ticker"]).isEmpty ? "?" : s(x["ticker"])
            return DiscoveryRow(id: "rh:\(s(x["contract"]).isEmpty ? t : s(x["contract"]))", symbol: t, chain: "Robinhood Chain",
                                facts: ([s(x["name"])] + extra).filter { !$0.isEmpty }, warning: nil)
        }
        switch tool {
        case "hub_rh_movers":
            let side = { (k: String, tag: String) in list(k).map { x in
                rh(x, [tag, pct(x["change_24h_pct"]).map { "24h \($0)" } ?? "", usd(x["price_usd"]).map { "price \($0)" } ?? "",
                       usd(x["tvl_usd"]).map { "pool \($0)" } ?? ""].filter { !$0.isEmpty }) } }
            return DiscoveryTable(title: "Robinhood Chain movers · 24h", rows: side("gainers", "gainer") + side("losers", "loser"), more: 0, note: s(r["note"]).nilIfEmpty)
        case "hub_rh_new_listings":
            let rows = list("recent_deployments").map { x in rh(x, [String(s(x["deployed_at"]).prefix(10))].filter { !$0.isEmpty }.map { "deployed \($0)" }) }
            return DiscoveryTable(title: "New Robinhood Chain listings", rows: rows, more: 0, note: s(r["note"]).nilIfEmpty)
        case "hub_rh_search":
            return DiscoveryTable(title: "Robinhood Chain token search", rows: list("matches").map { rh($0) }, more: 0, note: nil)
        case "hub_rh_quote":
            guard !s(r["ticker"]).isEmpty else { return nil }
            let stale = (r["is_stale"] as? Bool) == true || ((r["chainlink"] as? [String: Any])?["is_stale"] as? Bool) == true
            return DiscoveryTable(title: "Robinhood Chain oracle quote",
                                  rows: [rh(r, [usd(r["price_usd"]).map { "oracle \($0)" } ?? "", stale ? "oracle STALE" : ""].filter { !$0.isEmpty })], more: 0, note: nil)
        case "hub_rh_index":
            let all = list("stocks") + list("etfs")
            return DiscoveryTable(title: "Robinhood Chain stock & ETF tokens", rows: all.prefix(12).map { rh($0) }, more: max(0, all.count - 12), note: nil)
        case "hub_safe_trending":
            let rows = list("tokens").filter { s($0["status"]) == "ok" }.map { x -> DiscoveryRow in
                let hp = (x["honeypot"] as? [String: Any])?["verdict"] as? String
                let flags = (x["flags"] as? [String] ?? [])
                let facts = [usd(x["price_usd"]).map { "price \($0)" }, pct(x["change_24h"]).map { "24h \($0)" },
                             usd(x["liquidity_usd"]).map { "liquidity \($0)" }, hp.map { "tax check \($0)" },
                             (x["exit_risk"] as? String).map { "exit risk \($0)" },
                             flags.isEmpty ? nil : "flags: " + flags.map { flagText[$0] ?? $0 }.joined(separator: ", ")].compactMap { $0 }
                let warning = hp == "HONEYPOT" ? "measured as a honeypot" : flags.contains("IMPERSONATION_CHECK") ? "impersonates a pinned token" : nil
                return DiscoveryRow(id: "base:\(s(x["address"]).isEmpty ? s(x["symbol"]) : s(x["address"]))",
                                    symbol: s(x["symbol"]).isEmpty ? "?" : s(x["symbol"]), chain: "Base", facts: facts, warning: warning)
            }
            return DiscoveryTable(title: "Trending on Base · tax measured", rows: rows, more: 0, note: nil)
        default: return nil
        }
    }

    static func usd(_ v: Any?) -> String? {
        guard let n = (v as? NSNumber)?.doubleValue, n.isFinite else { return nil }
        if n >= 1e9 { return String(format: "$%.2fB", n / 1e9) }
        if n >= 1e6 { return String(format: "$%.2fM", n / 1e6) }
        if n >= 1e3 { return String(format: "$%.1fK", n / 1e3) }
        return n >= 1 ? String(format: "$%.2f", n) : "$" + String(format: "%.3g", n)
    }

    static func pct(_ v: Any?) -> String? {
        guard let n = (v as? NSNumber)?.doubleValue, n.isFinite else { return nil }
        return (n > 0 ? "+" : "") + String(format: "%.2f%%", n)
    }
}

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
