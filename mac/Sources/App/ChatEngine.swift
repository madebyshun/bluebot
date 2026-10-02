import Foundation

// MARK: - Chat with Blue Agent
//
// POST /api/devices/chat with the link token — Blue Chat's own pipeline,
// presets, live tools and credits, for the wallet this Mac is linked to, under
// the daily limit its owner set. The stream is SSE: `data: {json}` lines
// ending in one `data: [DONE]`. What BlueBot renders:
//   delta.text            → the answer, as it streams
//   tool_start/tool_done  → a tool line; a price-alert draft becomes a card
//                           you can arm here. A trade card is NOT built in
//                           BlueBot yet: it is named, and opens in Blue Chat.
//   insufficient_credits  → the message, with the balance
//   402 DEVICE_CAP        → today's limit for this Mac is used up

struct ChatPreset: Identifiable, Hashable {
    let id: String; let label: String; let credits: Int; let note: String
    static let all: [ChatPreset] = [
        .init(id: "fast", label: "Fast", credits: 10, note: "DeepSeek V4 Flash"),
        .init(id: "balanced", label: "Balanced", credits: 50, note: "Claude Sonnet 5"),
        .init(id: "deep", label: "Deep", credits: 200, note: "Claude Opus"),
        .init(id: "free", label: "Free", credits: 0, note: "no live tools"),
    ]
}

struct AlertDraft: Equatable { let rule: String; let priceNow: Double?; let automation: Bool; let body: [String: AnyCodableValue] }
enum ChatCard: Equatable { case alert(AlertDraft) }

struct BAChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String              // user · assistant
    var text: String
    var tools: [String] = []
    var cards: [ChatCard] = []
    var notice: String? = nil
}

/// JSON value kept as-is so an alert body round-trips to /api/watches untouched.
indirect enum AnyCodableValue: Equatable {
    case string(String), number(Double), bool(Bool), object([String: AnyCodableValue]), array([AnyCodableValue]), null
    init(_ any: Any) {
        switch any {
        case let s as String: self = .string(s)
        case let b as Bool: self = .bool(b)
        case let n as NSNumber: self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let d as [String: Any]: self = .object(d.mapValues(AnyCodableValue.init))
        case let a as [Any]: self = .array(a.map(AnyCodableValue.init))
        default: self = .null
        }
    }
    var any: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .object(let o): return o.mapValues(\.any)
        case .array(let a): return a.map(\.any)
        case .null: return NSNull()
        }
    }
}

@MainActor
final class ChatEngine: ObservableObject {
    static let shared = ChatEngine()

    /// Mirrored into AppState.chatHistory by count only: the island grows
    /// with the conversation (IslandContainer.chatPromptHeight).
    @Published private(set) var messages: [BAChatMessage] = [] {
        didSet {
            guard messages.count != AppState.shared.chatHistory.count else { return }
            AppState.shared.chatHistory = messages.map { ChatMessage(role: $0.role == "user" ? .user : .assistant, content: $0.text) }
        }
    }
    @Published private(set) var streaming = false {
        didSet { AppState.shared.stateOverride = streaming ? .thinking : nil }
    }
    @Published var preset: String = UserDefaults.standard.string(forKey: "chatPreset") ?? "balanced" {
        didSet { UserDefaults.standard.set(preset, forKey: "chatPreset") }
    }

    private var task: Task<Void, Never>?

    func clear() { task?.cancel(); messages = []; streaming = false }

    func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !streaming else { return }
        guard BlueAgentLink.shared.canChat else {
            messages.append(BAChatMessage(role: "assistant", text: "", notice: "Link BlueBot to your Blue Agent wallet with chat allowed (Account tab)."))
            return
        }
        messages.append(BAChatMessage(role: "user", text: t))
        messages.append(BAChatMessage(role: "assistant", text: ""))
        streaming = true
        let history = messages.dropLast().filter { !$0.text.isEmpty }.suffix(20).map { ["role": $0.role, "content": $0.text] }
        let body: [String: Any] = ["messages": Array(history), "tier": preset]
        task = Task { [weak self] in
            await self?.stream(body)
            self?.streaming = false
            BlueAgentLink.shared.refresh()
        }
    }

    func stop() { task?.cancel(); streaming = false }

    private func stream(_ body: [String: Any]) async {
        guard let url = URL(string: BlueAgentAPI.base + "/api/devices/chat"), let token = BlueAgentAPI.token else { return }
        var req = URLRequest(url: url, timeoutInterval: 180)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                var raw = ""; for try await line in bytes.lines { raw += line }
                let msg = ((try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any])?["error"] as? String
                notice(msg ?? "Blue Agent answered \(code).")
                return
            }
            for try await line in bytes.lines {
                if Task.isCancelled { return }
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { return }
                guard let j = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
                handle(j)
            }
        } catch {
            if !Task.isCancelled { notice("Connection lost: \(error.localizedDescription)") }
        }
    }

    private func handle(_ j: [String: Any]) {
        if let delta = j["delta"] as? [String: Any], let s = (delta["text"] ?? delta["value"]) as? String {
            mutateLast { $0.text += s }; return
        }
        switch j["type"] as? String {
        case "tool_start":
            if let tool = j["tool"] as? String { mutateLast { $0.tools.append(Self.toolLabel(tool)) } }
        case "tool_done":
            guard let tool = j["tool"] as? String, let r = j["result"] as? [String: Any] else { return }
            if tool == "set_price_alert", r["kind"] as? String == "price_alert_draft", let b = r["body"] as? [String: Any] {
                let d = AlertDraft(rule: (r["rule"] as? String) ?? "", priceNow: (r["priceNow"] as? NSNumber)?.doubleValue,
                                   automation: (r["automation"] as? Bool) ?? false, body: b.mapValues(AnyCodableValue.init))
                mutateLast { $0.cards.append(.alert(d)) }
            } else if tool == "prepare_swap" || tool == "robinhood_swap" {
                let what = [r["amountIn"], r["tokenIn"], r["tokenOut"]].compactMap { $0 as? String }.filter { !$0.isEmpty }
                notice("Trade prepared\(what.count == 3 ? ": \(what[0]) \(what[1]) → \(what[2])" : ""). Trading from BlueBot is not available yet; open Blue Chat to review and sign it with your wallet.")
            }
        case "insufficient_credits":
            let need = (j["needed"] as? NSNumber)?.intValue ?? 0, have = (j["balance"] as? NSNumber)?.intValue ?? 0
            notice((j["message"] as? String) ?? "Not enough credits: need \(need), have \(have). Top up on Blue Chat or switch to Fast.")
        case "auth_required", "wallet_required":
            notice("Blue Agent could not confirm this link. Link BlueBot again in Account. Nothing was charged.")
        default: break
        }
    }

    private func notice(_ m: String) { mutateLast { $0.notice = m } }

    private func mutateLast(_ f: (inout BAChatMessage) -> Void) {
        guard !messages.isEmpty else { return }
        f(&messages[messages.count - 1])
    }

    static func toolLabel(_ t: String) -> String {
        let map = ["hub_safe_trending": "Trending on Base", "new_tokens": "New launches", "check_token": "Token check",
                   "hub_token_price": "Price", "set_price_alert": "Price alert", "my_alerts": "Your alerts",
                   "prepare_swap": "Trade card", "check_wallet": "Wallet", "hub_rh_movers": "Robinhood movers",
                   "hub_honeypot": "Honeypot check", "hub_risk_gate": "Risk gate", "hub_liquidity_depth": "Liquidity"]
        return map[t] ?? t.replacingOccurrences(of: "hub_", with: "").replacingOccurrences(of: "_", with: " ")
    }
}
