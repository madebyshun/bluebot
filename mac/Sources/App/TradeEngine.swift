import Foundation

// MARK: - Trade on Base (0x), signed by the trader's own wallet
//
// The same path as Blue Chat's swap card (apps/web SwapCard.tsx):
//   1. pre-trade check on the token being bought (POST /api/pretrade-check):
//      PASS → go; WARN → the trader ticks "I read this"; BLOCK → no signing;
//   2. quote (GET /api/swap/quote — 0x allowance-holder, Base 8453);
//   3. approve the EXACT sell amount when 0x reports an allowance is needed;
//   4. send the swap from the trader's wallet (Privy), with Blue Agent's
//      ERC-8021 builder-code suffix, then record it (POST /api/actions) so
//      it lands in the wallet's Activity;
//   5. wait for the receipt and show it on Basescan.
// BlueBot never holds a key: every transaction is signed by the wallet.

struct TokenRef: Equatable, Hashable, Identifiable {
    let symbol: String
    let address: String       // 0x… or the native sentinel for ETH
    var id: String { address.lowercased() }
    var isNative: Bool { BaseRPC.isNative(address) }

    static let eth = TokenRef(symbol: "ETH", address: BaseRPC.native)
    static let usdc = TokenRef(symbol: "USDC", address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913")
    static let weth = TokenRef(symbol: "WETH", address: "0x4200000000000000000000000000000000000006")
    static let cbbtc = TokenRef(symbol: "cbBTC", address: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf")
    static let pinned: [TokenRef] = [.usdc, .eth, .weth, .cbbtc]

    /// "USDC", "eth", a 0x address → a token; unknown symbols → nil.
    @MainActor static func resolve(_ s: String) -> TokenRef? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("0x"), t.count == 42 { return pinned.first { $0.id == t.lowercased() } ?? TokenRef(symbol: short(t), address: t) }
        return pinned.first { $0.symbol.lowercased() == t.lowercased() }
            ?? MarketStore.shared.baseTokens.first { $0.sym.lowercased() == t.lowercased() }.map { TokenRef(symbol: $0.sym, address: $0.addr) }
    }

    static func short(_ a: String) -> String { a.count > 12 ? "\(a.prefix(6))…\(a.suffix(4))" : a }
}

struct PreTradeVerdict: Equatable {
    let verdict: String            // PASS · WARN · BLOCK
    let label: String
    let reasons: [(level: String, text: String)]
    static func == (a: PreTradeVerdict, b: PreTradeVerdict) -> Bool { a.verdict == b.verdict && a.label == b.label && a.reasons.map(\.text) == b.reasons.map(\.text) }
}

@MainActor
final class TradeEngine: ObservableObject {
    static let shared = TradeEngine()

    enum Step: Equatable {
        case idle, checking, quoting, ready, approving, swapping
        case done(hash: String, ok: Bool)
        case failed(String)
    }

    @Published var sell: TokenRef = .usdc { didSet { invalidate() } }
    @Published var buy: TokenRef = .eth { didSet { invalidate(); check = nil } }
    @Published var amount: String = "" { didSet { invalidate() } }
    @Published var slippageBps: Int = 100 { didSet { invalidate() } }
    @Published var acknowledgedWarn = false
    @Published private(set) var step: Step = .idle
    @Published private(set) var check: PreTradeVerdict?
    @Published private(set) var expectedOut: String?
    @Published private(set) var minOut: String?
    @Published private(set) var feeNote: String?
    @Published private(set) var balance: String?

    private var quote: [String: Any]?
    private var sellAmountBase: BigUInt?
    var source = "wallet"          // "chat" when it came from a chat card

    private func invalidate() {
        quote = nil; expectedOut = nil; minOut = nil; feeNote = nil
        if case .done = step { return }
        if step != .approving && step != .swapping { step = .idle }
    }

    func load(_ d: SwapDraft) {
        source = "chat"
        sell = TokenRef.resolve(d.tokenInAddress.isEmpty ? d.tokenIn : d.tokenInAddress) ?? .usdc
        buy = TokenRef.resolve(d.tokenOutAddress.isEmpty ? d.tokenOut : d.tokenOutAddress) ?? .eth
        amount = d.amountIn
        acknowledgedWarn = false
        step = .idle
    }

    func prepare(buy token: TokenRef) {
        source = "wallet"; buy = token; if sell == token { sell = token.isNative ? .usdc : .eth }
        acknowledgedWarn = false; step = .idle
    }

    var canSign: Bool {
        guard step == .ready, let c = check else { return false }
        return c.verdict == "PASS" || (c.verdict == "WARN" && acknowledgedWarn)
    }

    // MARK: Check + quote

    func review() {
        guard let wallet = BlueAgentSession.shared.wallet else { step = .failed("Sign in with your email first."); return }
        Task {
            do {
                step = .checking
                check = try await Self.preTradeCheck(chain: "base", kind: "swap", token: buy.isNative ? "ETH" : buy.address)
                if check?.verdict == "BLOCK" { step = .ready; return }
                step = .quoting
                let dec = try await BaseRPC.decimals(of: sell.address)
                let bal = try await BaseRPC.balance(of: sell.address, owner: wallet)
                balance = Units.format(bal, decimals: dec)
                guard let amt = try resolveAmount(amount, balance: bal, decimals: dec), !amt.isZero else {
                    throw BlueAgentSession.err("Enter an amount, or all / half / 25%.")
                }
                if bal < amt { throw BlueAgentSession.err("Not enough \(sell.symbol): you have \(balance ?? "0").") }
                sellAmountBase = amt
                try await fetchQuote(amount: amt, taker: wallet)
                step = .ready
            } catch {
                step = .failed(error.localizedDescription)
            }
        }
    }

    private func resolveAmount(_ s: String, balance: BigUInt, decimals: Int) throws -> BigUInt? {
        let t = s.lowercased().trimmingCharacters(in: .whitespaces)
        func pct(_ p: Int) -> BigUInt { balance.multiplied(by: UInt32(p)).divided(by: 100) }
        var v: BigUInt?
        if t == "all" || t == "max" { v = balance }
        else if t == "half" { v = pct(50) }
        else if t.hasSuffix("%"), let p = Int(t.dropLast()), (1...100).contains(p) { v = p == 100 ? balance : pct(p) }
        else { v = Units.parse(t, decimals: decimals) }
        // Keep a little ETH for gas when spending all of it.
        if sell.isNative, let x = v, x == balance, let reserve = Units.parse("0.00005", decimals: 18) {
            v = x.minus(reserve) ?? .zero
        }
        return v
    }

    private func fetchQuote(amount: BigUInt, taker: String) async throws {
        var c = URLComponents(string: BlueAgentAPI.base + "/api/swap/quote")!
        c.queryItems = [
            .init(name: "sellToken", value: sell.isNative ? BaseRPC.native : sell.address),
            .init(name: "buyToken", value: buy.isNative ? BaseRPC.native : buy.address),
            .init(name: "sellAmount", value: amount.decimalString),
            .init(name: "slippageBps", value: String(slippageBps)),
            .init(name: "taker", value: taker),
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        guard let q = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BlueAgentSession.err("No quote.") }
        if q["needsKey"] != nil { throw BlueAgentSession.err("Quotes are unavailable right now.") }
        if let e = q["error"] as? String { throw BlueAgentSession.err("No route: \(e)") }
        guard q["transaction"] is [String: Any], let buyAmt = (q["buyAmount"] as? String).flatMap(BigUInt.init(decimal:)) else {
            throw BlueAgentSession.err("No route for this trade.")
        }
        let bdec = try await BaseRPC.decimals(of: buy.address)
        expectedOut = "\(Units.format(buyAmt, decimals: bdec)) \(buy.symbol)"
        if let m = (q["minBuyAmount"] as? String).flatMap(BigUInt.init(decimal:)) { minOut = "\(Units.format(m, decimals: bdec)) \(buy.symbol)" }
        if let fee = (q["fees"] as? [String: Any])?["zeroExFee"] as? [String: Any], let a = fee["amount"] as? String {
            feeNote = "0x fee: \(a) base units"
        } else { feeNote = nil }
        quote = q
    }

    // MARK: Sign

    func sign() {
        guard canSign, let wallet = BlueAgentSession.shared.wallet, let amt = sellAmountBase else { return }
        Task {
            do {
                // Approve exactly the sell amount when 0x needs an allowance.
                if !sell.isNative, let spender = ((quote?["issues"] as? [String: Any])?["allowance"] as? [String: Any])?["spender"] as? String {
                    step = .approving
                    let h = try await BlueAgentSession.shared.sendBaseTransaction(to: sell.address, data: ABI.approve(spender: spender, amount: amt), value: .zero)
                    guard try await BaseRPC.waitForReceipt(h) else { throw BlueAgentSession.err("The approval reverted.") }
                    try await fetchQuote(amount: amt, taker: wallet)   // a fresh quote after the approval
                }
                guard let tx = quote?["transaction"] as? [String: Any], let to = tx["to"] as? String, let data = tx["data"] as? String else {
                    throw BlueAgentSession.err("The quote expired. Review again.")
                }
                step = .swapping
                let value = (tx["value"] as? String).flatMap(BigUInt.init(decimal:)) ?? .zero
                let hash = try await BlueAgentSession.shared.sendBaseTransaction(to: to, data: data + Self.builderSuffix, value: value)
                await record(hash: hash, wallet: wallet, amount: amt)
                let ok = try await BaseRPC.waitForReceipt(hash)
                step = .done(hash: hash, ok: ok)
                SoundEngine.shared.play(ok ? "proud" : "error")
                LiveFeed.shared.refreshNow()
            } catch {
                step = .failed(error.localizedDescription)
            }
        }
    }

    func reset() { step = .idle; check = nil; acknowledgedWarn = false; quote = nil; expectedOut = nil; minOut = nil }

    /// Blue Agent's ERC-8021 builder code (apps/web src/constants/builderCode.ts), as on the web.
    static let builderSuffix = "62635f32656a72333578630b0080218021802180218021802180218021"

    private func record(hash: String, wallet: String, amount: BigUInt) async {
        var body: [String: Any] = [
            "address": wallet.lowercased(), "kind": "swap", "chain": "base", "source": source,
            "params": ["tokenIn": sell.address, "tokenOut": buy.address, "amountIn": amount.decimalString,
                       "slippageBps": slippageBps, "symIn": sell.symbol, "symOut": buy.symbol],
            "tx_hash": hash,
        ]
        if let q = quote, let b = q["buyAmount"] as? String, let m = q["minBuyAmount"] as? String {
            body["quote"] = ["venue": "0x", "expected_out": b, "min_out": m, "unit": "base"]
        }
        if let c = check { body["check"] = ["verdict": c.verdict, "reasons": c.reasons.map(\.text)] }
        _ = try? await BlueAgentSession.shared.authed("POST", "/api/actions", json: body)
    }

    // MARK: Pre-trade check (also used by Check)

    static func preTradeCheck(chain: String, kind: String, token: String) async throws -> PreTradeVerdict {
        let (data, code) = try await BlueAgentSession.shared.authed("POST", "/api/pretrade-check", json: ["chain": chain, "kind": kind, "token": token])
        guard code == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any], let v = j["verdict"] as? String else {
            throw BlueAgentSession.err(code == 429 ? "The check is busy. Try again in a moment." : "The pre-trade check did not run.")
        }
        let reasons = (j["reasons"] as? [[String: Any]] ?? []).map { (level: ($0["level"] as? String) ?? "INFO", text: ($0["text"] as? String) ?? "") }
        return PreTradeVerdict(verdict: v, label: (j["label"] as? String) ?? token, reasons: reasons)
    }
}
