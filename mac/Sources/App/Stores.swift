import Foundation
import AppKit

// MARK: - Market (public, free — no sign-in)
//
//   GET /api/base-tokens   → majors on Base (DexScreener, deepest pair), 5-min cache
//   GET /api/hood/snapshot → stock tokens on Base (Coinbase B20) and Robinhood
//                            Chain: Chainlink oracle, DEX price, drift, session
// Every number shown names its chain and its source.

struct BaseTokenRow: Identifiable, Equatable {
    let sym: String; let addr: String; let price: Double?; let change24h: Double?; let vol24h: Double?
    var id: String { addr.lowercased() }
}

struct StockRow: Identifiable, Equatable {
    let ticker: String; let name: String; let chain: String; let contract: String
    let oracle: Double?; let dex: Double?; let drift: Double?; let session: String; let isOpen: Bool
    let quarantined: Bool
    var id: String { "\(chain):\(contract.lowercased())" }
}

@MainActor
final class MarketStore: ObservableObject {
    static let shared = MarketStore()
    @Published private(set) var baseTokens: [BaseTokenRow] = []
    /// Starred tokens that are not in /api/base-tokens (pinned from a check),
    /// priced one by one through Blue Agent's MCP `hub_token_price`.
    @Published private(set) var pinnedExtra: [BaseTokenRow] = []
    var allBase: [BaseTokenRow] { baseTokens + pinnedExtra }
    @Published private(set) var stocks: [StockRow] = []
    @Published private(set) var updated: Date?
    @Published private(set) var error: String?
    @Published var watchlist: [String] = UserDefaults.standard.stringArray(forKey: "watchlist") ?? [] {
        didSet { UserDefaults.standard.set(watchlist, forKey: "watchlist") }
    }
    private var loading = false

    func toggleWatch(_ id: String) {
        if watchlist.contains(id) { watchlist.removeAll { $0 == id }; pinnedExtra.removeAll { $0.id == id } }
        else { watchlist.append(id); Task { await refreshPinned() } }
    }

    func isPinned(_ address: String) -> Bool { watchlist.contains(address.lowercased()) }

    /// Prices for starred tokens outside the base list. A token whose price
    /// cannot be read keeps its row with no price — never a made-up one.
    func refreshPinned() async {
        let core = Set(baseTokens.map(\.id))
        var rows: [BaseTokenRow] = []
        for id in watchlist where !core.contains(id) && id.hasPrefix("0x") && id.count == 42 {
            if let r = await Self.price(id) { rows.append(r) }
            else { rows.append(pinnedExtra.first { $0.id == id } ?? BaseTokenRow(sym: "\(id.prefix(6))…\(id.suffix(4))", addr: id, price: nil, change24h: nil, vol24h: nil)) }
        }
        pinnedExtra = rows
    }

    nonisolated static func price(_ address: String) async -> BaseTokenRow? {
        let base = UserDefaults.standard.string(forKey: "apiBase").flatMap { $0.isEmpty ? nil : $0 } ?? BlueAgentAPI.defaultBase
        guard let url = URL(string: base + "/api/mcp") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": "hub_token_price", "arguments": ["token": address]]])
        guard let (data, _) = try? await URLSession.shared.data(for: req), let raw = String(data: data, encoding: .utf8) else { return nil }
        let json = raw.split(separator: "\n").first { $0.hasPrefix("data:") }.map { String($0.dropFirst(5)) } ?? raw
        guard let env = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let text = (((env["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String),
              let t = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let sym = t["symbol"] as? String else { return nil }
        return BaseTokenRow(sym: sym, addr: address, price: (t["price_usd"] as? NSNumber)?.doubleValue,
                            change24h: ((t["change"] as? [String: Any])?["h24"] as? NSNumber)?.doubleValue,
                            vol24h: (t["volume_24h"] as? NSNumber)?.doubleValue)
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                async let a = Self.fetch("/api/base-tokens")
                async let b = Self.fetch("/api/hood/snapshot")
                let (da, db) = try await (a, b)
                let bt = (try? JSONSerialization.jsonObject(with: da) as? [String: Any]) ?? [:]
                let hs = (try? JSONSerialization.jsonObject(with: db) as? [String: Any]) ?? [:]
                baseTokens = (bt["tokens"] as? [[String: Any]] ?? []).compactMap { t in
                    guard let s = t["sym"] as? String, let a = t["addr"] as? String else { return nil }
                    return BaseTokenRow(sym: s, addr: a, price: (t["price"] as? NSNumber)?.doubleValue,
                                        change24h: (t["change24h"] as? NSNumber)?.doubleValue, vol24h: (t["vol24h"] as? NSNumber)?.doubleValue)
                }
                let tickers = ((hs["snapshot"] as? [String: Any])?["tickers"] as? [[String: Any]]) ?? []
                stocks = tickers.compactMap { t in
                    guard let tk = t["ticker"] as? String, let c = t["contract"] as? String else { return nil }
                    let m = t["market"] as? [String: Any]
                    return StockRow(ticker: tk, name: (t["name"] as? String) ?? tk, chain: (t["chain"] as? String) ?? "robinhood", contract: c,
                                    oracle: (t["oracle_usd"] as? NSNumber)?.doubleValue, dex: (t["dex_usd"] as? NSNumber)?.doubleValue,
                                    drift: (t["drift_pct"] as? NSNumber)?.doubleValue, session: (m?["session"] as? String) ?? "",
                                    isOpen: (m?["is_open"] as? Bool) ?? false, quarantined: (t["provenance"] as? String) == "quarantined")
                }
                .sorted { ($0.chain == "base" ? 0 : 1, $0.ticker) < ($1.chain == "base" ? 0 : 1, $1.ticker) }
                updated = Date(); error = nil
                await refreshPinned()
            } catch { self.error = error.localizedDescription }
        }
    }

    nonisolated static func fetch(_ path: String) async throws -> Data {
        let base = UserDefaults.standard.string(forKey: "apiBase").flatMap { $0.isEmpty ? nil : $0 } ?? BlueAgentAPI.defaultBase
        let (data, _) = try await URLSession.shared.data(from: URL(string: base + path)!)
        return data
    }
}

// MARK: - Alerts (/api/watches, signed in)

struct WatchRow: Identifiable, Equatable {
    let id: String; let symbol: String; let chain: String; let rule: String; let active: Bool; let automation: Bool
}

@MainActor
final class AlertsStore: ObservableObject {
    static let shared = AlertsStore()
    @Published private(set) var watches: [WatchRow] = []
    @Published private(set) var error: String?
    @Published private(set) var busy = false

    func refresh() {
        guard BlueAgentLink.shared.isLinked else { watches = []; return }
        Task {
            guard let (data, code) = try? await BlueAgentAPI.authed("GET", "/api/watches") else { error = "Could not reach Blue Agent."; return }
            guard code == 200, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { error = "Alerts are unavailable right now."; return }
            watches = (j["watches"] as? [[String: Any]] ?? []).compactMap(Self.row)
            error = nil
        }
    }

    static func row(_ w: [String: Any]) -> WatchRow? {
        guard let id = w["id"] as? String else { return nil }
        let sym = (w["symbol"] as? String) ?? "?"
        let chain = (w["chain"] as? String) == "robinhood" ? "Robinhood Chain" : "Base"
        let kind = w["kind"] as? String, dir = w["direction"] as? String
        let th = (w["threshold"] as? NSNumber)?.doubleValue ?? 0
        var rule = kind == "price"
            ? "\(dir == "above" ? "rises to or above" : "falls to or below") $\(Fmt.price(th))"
            : "\(dir == "up" ? "up" : "down") \(Fmt.num(th))% over \((w["window"] as? String) == "1h" ? "1 hour" : "24 hours")"
        if let t = w["trade"] as? [String: Any] { rule += " → prepare a \((t["side"] as? String) ?? "") of \((t["amount"] as? String) ?? "")" }
        if let c = w["checkAt"] as? [String: Any] { rule = "\((c["schedule"] as? String) == "weekly" ? "weekly" : "daily") \((c["time"] as? String) ?? ""): " + rule }
        return WatchRow(id: id, symbol: sym, chain: chain, rule: rule, active: (w["active"] as? Bool) ?? true,
                        automation: w["trade"] != nil || w["checkAt"] != nil)
    }

    /// Arms a draft (from chat) or a quick alert. Returns an error message, or nil on success.
    func create(_ body: [String: Any]) async -> String? {
        busy = true; defer { busy = false }
        var b = body
        if var c = b["check_at"] as? [String: Any], c["tz"] == nil { c["tz"] = TimeZone.current.identifier; b["check_at"] = c }
        guard let (data, code) = try? await BlueAgentAPI.authed("POST", "/api/watches", json: b) else { return "Could not reach Blue Agent." }
        if code == 200 { refresh(); SoundEngine.shared.play("pop"); return nil }
        if code == 403 { return "This link can't set alerts. In Account, link again and allow alerts." }
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String ?? "Blue Agent refused the alert (\(code))."
    }

    func setActive(_ id: String, _ active: Bool) {
        Task { _ = try? await BlueAgentAPI.authed("PATCH", "/api/watches", json: ["id": id, "active": active]); refresh() }
    }

    func delete(_ id: String) {
        Task { _ = try? await BlueAgentAPI.authed("DELETE", "/api/watches?id=\(id)"); refresh() }
    }
}

// MARK: - Live feed: activity + fired alerts → the island
//
// GET /api/devices/feed with the link token: the wallet's timeline (fired
// alerts, signed trades, automation checks, pre-trade blocks). Every 180 s —
// Blue Agent evaluates alerts every 5 minutes, so faster buys nothing. The
// first read only fills the view.

struct LiveEvent: Equatable, Identifiable {
    let id: String
    let kind: String              // alert · trade · automation_checked · task_run · task_failed · blocked
    let title: String
    let detail: String?
    let chain: String?
    let at: Double
    var href: String? = nil
}

@MainActor
final class LiveFeed: ObservableObject {
    static let shared = LiveFeed()
    @Published private(set) var items: [LiveEvent] = []
    @Published private(set) var current: LiveEvent?
    @Published private(set) var lastRead: Date?
    @Published private(set) var lastError: String?

    private var loop: Task<Void, Never>?
    private var seen: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "liveSeenIds") ?? [])
    private var primed = false
    static var taskId: String { PillCatalog.defaultMainPillId }

    func start() {
        loop?.cancel(); primed = false
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.readOnce()
                try? await Task.sleep(nanoseconds: 180 * 1_000_000_000)
            }
        }
    }

    func refreshNow() { Task { await readOnce() } }

    private func readOnce() async {
        var events: [LiveEvent] = []
        guard BlueAgentLink.shared.isLinked else { items = []; return }
        do {
            let feed = try await BlueAgentAPI.feed()
            events = feed.items.map { LiveEvent(id: $0.id, kind: $0.kind, title: $0.title, detail: $0.detail, chain: $0.chain, at: $0.at, href: $0.href) }
            AlertsStore.shared.refresh()
        } catch BlueAgentAPI.Failure.unlinked {
            BlueAgentLink.shared.refresh(); items = []; return
        } catch {
            lastError = "Activity could not be read."; return
        }
        events.sort { $0.at > $1.at }
        items = events; lastRead = Date(); lastError = nil
        surface(events)
    }

    private func surface(_ newestFirst: [LiveEvent]) {
        let fresh = newestFirst.filter { !seen.contains($0.id) }
        seen.formUnion(newestFirst.map(\.id))
        UserDefaults.standard.set(Array(seen.suffix(400)), forKey: "liveSeenIds")
        setSteps(Array(newestFirst.prefix(4).reversed()).map(Self.line))
        guard primed else { primed = true; return }
        if let a = fresh.first(where: { $0.kind == "alert" }) { show(a, view: .finished) }
        else if let b = fresh.first(where: { $0.kind == "blocked" }) { show(b, view: .error) }
        else if !fresh.isEmpty { NotificationCenter.default.post(name: .hookReveal, object: nil) }
    }

    private func show(_ e: LiveEvent, view: IslandView) {
        current = e
        let state = AppState.shared
        guard let i = state.tasks.firstIndex(where: { $0.id == Self.taskId }) else { return }
        state.tasks[i].state = view == .error ? .error : .finished
        state.focusId = Self.taskId
        SoundEngine.shared.play(view == .error ? "error" : "finish")
        if state.mode == .expanded { state.view = view } else { NotificationCenter.default.post(name: .hookExpand, object: view) }
    }

    func dismiss() {
        current = nil
        let state = AppState.shared
        if let i = state.tasks.firstIndex(where: { $0.id == Self.taskId }) { state.tasks[i].state = .idle; state.tasks[i].pillBadge = nil }
    }

    private func setSteps(_ lines: [String]) {
        let state = AppState.shared
        guard let i = state.tasks.firstIndex(where: { $0.id == Self.taskId }) else { return }
        state.tasks[i].steps = lines
    }

    static func line(_ e: LiveEvent) -> String {
        let chain = e.chain == "robinhood" ? " · Robinhood Chain" : e.chain == "base" ? " · Base" : ""
        return "\(e.title)\(chain)"
    }
}

// MARK: - Formatting

enum Fmt {
    static func price(_ v: Double?) -> String {
        guard let v else { return "—" }
        if v >= 1000 { return String(format: "%.0f", v) }
        if v >= 1 { return String(format: "%.2f", v) }
        if v >= 0.01 { return String(format: "%.4f", v) }
        return String(format: "%.6f", v)
    }
    static func num(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }
    static func pct(_ v: Double?) -> String { guard let v else { return "—" }; return (v >= 0 ? "+" : "") + String(format: "%.2f%%", v) }
    static func usdCompact(_ v: Double?) -> String {
        guard let v else { return "—" }
        if v >= 1e9 { return String(format: "$%.2fB", v / 1e9) }
        if v >= 1e6 { return String(format: "$%.1fM", v / 1e6) }
        if v >= 1e3 { return String(format: "$%.0fK", v / 1e3) }
        return String(format: "$%.0f", v)
    }
}
