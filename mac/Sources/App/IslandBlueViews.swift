import AppKit
import Charts
import SwiftUI

// MARK: - BlueBot in the notch, the Coucou way
//
// Every feature lives in the island itself: the character sits on the left,
// the card on the right (content starts at x 84, as Coucou's prompt/result
// cards do). Header tabs switch between them:
//   ⌂ overview · 💬 chat · 📈 market · 🔔 alerts · ☰ activity · ⚙︎ account
// There is no separate window: BlueBot is the notch.

enum Ink {
    static let text = Color(hex: "#F1F2F4")
    static let dim = Color(hex: "#9398A1")
    static let faint = Color(hex: "#6E737C")
    static let row = Color.white.opacity(0.05)
    static let accent = Color(hex: "#4FC3F7")
    static let green = Color(hex: "#34D399")
    static let red = Color(hex: "#F87171")
    static let amber = Color(hex: "#F5A524")
}

/// The left inset every card shares, clearing the character.
private let lead: CGFloat = 84

private struct CardTitle: View {
    let title: String
    var sub: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if let sub { Text(sub).font(.system(size: 11)).foregroundColor(Ink.faint).lineLimit(1) }
            Spacer(minLength: 4)
        }
    }
}

private struct RowPill<L: View, R: View>: View {
    @ViewBuilder var left: L
    @ViewBuilder var right: R
    var body: some View {
        HStack(spacing: 8) { left; Spacer(minLength: 6); right }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Ink.row).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Shown in place of a card's content until the wallet is linked.
private struct LinkFirst: View {
    let what: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Link your Blue Agent wallet to \(what).").font(.system(size: 15, weight: .semibold))
            Text("The wallet you already use on blueagent.dev. No new wallet, no key on this Mac.")
                .font(.system(size: 12)).foregroundColor(Ink.dim)
            HStack(spacing: 8) {
                PrimaryButton("Link wallet") { AppState.shared.view = .settings; BlueAgentLink.shared.beginLink() }
            }
        }
    }
}

// MARK: Chat

struct BlueChatIslandView: View {
    /// Discovery, price, analysis, alert — one of each kind of thing chat can do.
    static let suggestions = [
        "what's trending on Base?",
        "price of VIRTUAL and AERO on Base right now",
        "analyze AERO on Base: liquidity, tax and risk",
        "alert me if ETH on Base drops 5% in 24h",
    ]
    @ObservedObject var chat = ChatEngine.shared
    @ObservedObject var link = BlueAgentLink.shared
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .brand)
            Group {
                if !link.isLinked { LinkFirst(what: "chat") }
                else if link.me != nil && !link.canChat {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chat isn't allowed for this Mac.").font(.system(size: 15, weight: .semibold))
                        Text("Link again and tick \"Chat with Blue Agent\" on the web.").font(.system(size: 12)).foregroundColor(Ink.dim)
                        PrimaryButton("Change") { AppState.shared.view = .settings; link.relink() }
                    }
                } else { conversation }
            }
            .padding(.leading, lead).padding(.trailing, 16).padding(.top, 12).padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.bottom, 10)
        .onAppear { focused = true }
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 6) {
            if chat.messages.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(Self.suggestions, id: \.self) { s in
                        Button { chat.send(s) } label: {
                            Text(s).font(.system(size: 11.5)).foregroundColor(Ink.dim).lineLimit(2).multilineTextAlignment(.leading)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Ink.row).clipShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(chat.messages) { m in bubble(m).id(m.id) }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: chat.messages.last?.text) { _, _ in
                        if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                    .onAppear { if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                }
                .frame(maxHeight: .infinity)
            }

            HStack(spacing: 6) {
                if !chat.messages.isEmpty {
                    Button("New chat") { chat.clear() }.buttonStyle(.plain).font(.system(size: 10.5)).foregroundColor(Ink.faint)
                }
                Spacer()
                if let c = link.credits { Text("\(c) credits").font(.system(size: 10.5)).foregroundColor(c < 50 ? Ink.amber : Ink.faint) }
                Menu {
                    ForEach(ChatPreset.all) { p in Button("\(p.label) · \(p.credits) cr · \(p.note)") { chat.preset = p.id } }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(Ink.accent).frame(width: 6, height: 6)
                        Text(ChatPreset.all.first { $0.id == chat.preset }.map { "\($0.label) · \($0.credits) cr" } ?? chat.preset)
                            .font(.system(size: 10.5, weight: .medium)).foregroundColor(Color(hex: "#7B8089"))
                    }
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 4).background(Color.white.opacity(0.06)).clipShape(Capsule())
            }

            HStack(spacing: 8) {
                TextField(chat.messages.isEmpty ? "Ask Blue Agent…" : "Continue…", text: $text)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($focused).onSubmit(send)
                if chat.streaming {
                    Button(action: chat.stop) { Image(systemName: "stop.fill").font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: "#0B0C0E")) }
                        .buttonStyle(SendButtonStyle())
                } else {
                    Button(action: send) { Image(systemName: "arrow.up").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#0B0C0E")) }
                        .buttonStyle(SendButtonStyle()).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
            .simultaneousGesture(TapGesture().onEnded { focused = true })
        }
    }

    @ViewBuilder private func bubble(_ m: BAChatMessage) -> some View {
        if m.role == "user" {
            HStack { Spacer(minLength: 32)
                Text(m.text).font(.system(size: 12.5)).foregroundColor(Ink.text).textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.13)).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                if !m.tools.isEmpty {
                    Text(m.tools.map { "⚙︎ \($0)" }.joined(separator: "  ")).font(.system(size: 10.5)).foregroundColor(Ink.faint)
                }
                if !m.text.isEmpty {
                    Text(LocalizedStringKey(m.text)).font(.system(size: 12.5)).foregroundColor(Color(hex: "#C8CDD4"))
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                } else if chat.streaming && m.id == chat.messages.last?.id {
                    ShimmeringText(m.tools.last.map { "Blue Agent is checking \($0)…" } ?? "Blue Agent is thinking…").font(.system(size: 12.5))
                }
                ForEach(Array(m.cards.enumerated()), id: \.offset) { _, c in
                    switch c {
                    case .alert(let d): IslandAlertDraft(draft: d)
                    case .table(let t): DiscoveryTableView(table: t)
                    }
                }
                if let n = m.notice { Text(n).font(.system(size: 11.5)).foregroundColor(Ink.amber).fixedSize(horizontal: false, vertical: true) }
                if m.needsTopUp { PrimaryButton("Top up credits") { BlueAgentLink.open(BlueAgentAPI.topUpURL) } }
            }
        }
    }

    private func send() { let t = text; text = ""; chat.send(t) }
}

private struct IslandAlertDraft: View {
    let draft: AlertDraft
    @ObservedObject var alerts = AlertsStore.shared
    @State private var armed = false
    @State private var err: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            RowPill {
                VStack(alignment: .leading, spacing: 1) {
                    Text(draft.rule.prefix(1).uppercased() + draft.rule.dropFirst()).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                    Text(draft.priceNow.map { "now $\(Fmt.price($0)) · checked every 5 min · free" } ?? "checked every 5 min · free")
                        .font(.system(size: 10.5)).foregroundColor(Ink.faint)
                }
            } right: {
                if armed { Text("Armed").font(.system(size: 11.5, weight: .semibold)).foregroundColor(Ink.green) }
                else {
                    Button(alerts.busy ? "…" : "Arm") {
                        Task { let e = await alerts.create(draft.body.mapValues(\.any)); if let e { err = e } else { armed = true } }
                    }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4).background(Ink.text).foregroundColor(Color(hex: "#0B0C0E")).clipShape(Capsule())
                    .disabled(alerts.busy)
                }
            }
            if let err { Text(err).font(.system(size: 10.5)).foregroundColor(Ink.amber) }
        }
    }
}

// MARK: Market

struct MarketIslandView: View {
    @ObservedObject var market = MarketStore.shared
    @State private var dragging: String?
    @State private var stocks = false
    @State private var input = ""
    @State private var verdict: PreTradeVerdict?
    @State private var checking = false
    @State private var checkError: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: .brand)
            if let f = market.focus {
                TokenChartView(focus: f).padding(.leading, lead).padding(.trailing, 16).padding(.vertical, 12)
            } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("Market").font(.system(size: 15, weight: .semibold))
                    seg("Base", !stocks) { stocks = false }
                    seg("Stocks", stocks) { stocks = true }
                    Spacer()
                }
                checkField
                if let v = verdict { verdictRow(v) }
                else if let e = checkError { Text(e).font(.system(size: 11)).foregroundColor(Ink.amber) }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        if stocks {
                            ForEach(market.displayStocks) { s in
                                stockRow(s)
                                    .contentShape(Rectangle())
                                    .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) {
                                        market.focus = .init(address: s.contract, symbol: s.ticker, chain: s.chain, pool: s.poolRef)
                                    } }
                                    .opacity(dragging == s.id ? 0.4 : 1)
                                    .onDrag { dragging = s.id; return NSItemProvider(object: s.id as NSString) }
                                    .onDrop(of: [.text], delegate: RowDrop(target: s.id, dragging: $dragging, move: market.moveStock))
                            }
                            if !market.stockHidden.isEmpty {
                                Button("Show \(market.stockHidden.count) removed") { market.restoreStocks() }
                                    .buttonStyle(.plain).font(.system(size: 10.5)).foregroundColor(Ink.accent)
                            }
                        } else {
                            ForEach(market.displayBase) { t in
                                baseRow(t)
                                    .contentShape(Rectangle())
                                    .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { market.focus = .init(address: t.addr, symbol: t.sym) } }
                                    .opacity(dragging == t.id ? 0.4 : 1)
                                    .onDrag { dragging = t.id; return NSItemProvider(object: t.id as NSString) }
                                    .onDrop(of: [.text], delegate: RowDrop(target: t.id, dragging: $dragging, move: market.move))
                            }
                            if !market.hidden.isEmpty {
                                Button("Show \(market.hidden.count) removed") { market.restoreHidden() }
                                    .buttonStyle(.plain).font(.system(size: 10.5)).foregroundColor(Ink.accent)
                            }
                        }
                        if (stocks ? market.displayStocks.isEmpty && market.stockHidden.isEmpty : market.displayBase.isEmpty && market.hidden.isEmpty) {
                            Text(market.error ?? "Reading prices…").font(.system(size: 12)).foregroundColor(Ink.dim)
                        }
                    }
                }
                Text(stocks ? "Oracle: Chainlink · DEX: the token's pool · stock tokens are not shares" : "Prices: DexScreener, deepest Base pool · tap a token for its chart")
                    .font(.system(size: 10)).foregroundColor(Ink.faint)
            }
            .padding(.leading, lead).padding(.trailing, 16).padding(.vertical, 12)
            }
        }
        .padding(.bottom, 10)
        .onAppear { market.refresh() }
    }

    private func seg(_ t: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 11, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 3)
                .foregroundColor(on ? Color(hex: "#F5F6F8") : Ink.faint)
                .background(on ? Color(hex: "#1D1F23") : Color.clear).clipShape(Capsule())
        }.buttonStyle(.plain)
    }

    private var checkField: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield").font(.system(size: 11)).foregroundColor(Ink.faint)
            TextField("Check a token: paste a 0x address on Base", text: $input).textFieldStyle(.plain).font(.system(size: 12)).onSubmit(run)
            if checking { ProgressView().controlSize(.small) }
            else if isAddress(input) {
                Button(action: run) { Image(systemName: "arrow.up").font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: "#0B0C0E")) }
                    .buttonStyle(SendButtonStyle())
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func verdictRow(_ v: PreTradeVerdict) -> some View {
        let c = v.verdict == "BLOCK" ? Ink.red : v.verdict == "WARN" ? Ink.amber : Ink.green
        return HStack(alignment: .top, spacing: 8) {
            Text(v.verdict).font(.system(size: 11, weight: .heavy)).foregroundColor(Color(hex: "#0B0C0E"))
                .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(c))
            VStack(alignment: .leading, spacing: 1) {
                Text(v.label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(v.reasons.first?.text ?? "Nothing measured against it.").font(.system(size: 11)).foregroundColor(Ink.dim).lineLimit(3)
                if !v.poolTokens.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(v.poolTokens, id: \.address) { t in
                            Button("Check \(t.symbol)") { input = t.address; run() }
                                .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3).background(Ink.accent.opacity(0.14)).foregroundColor(Ink.accent).clipShape(Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Button { verdict = nil; input = "" } label: { Image(systemName: "xmark").font(.system(size: 9)).foregroundColor(Ink.faint) }.buttonStyle(.plain)
                if !v.notAToken && !v.address.isEmpty {
                    Button { market.focus = .init(address: v.address, symbol: v.label.count <= 12 ? v.label : BlueAgentLink.short(v.address)) } label: {
                        Label("Chart", systemImage: "chart.xyaxis.line").font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundColor(Ink.accent)
                    let pinned = market.isPinned(v.address)
                    Button { market.toggleWatch(v.address) } label: {
                        Label(pinned ? "Pinned" : "Pin", systemImage: pinned ? "star.fill" : "star").font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundColor(Ink.amber)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6).background(c.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func baseRow(_ t: BaseTokenRow) -> some View {
        RowPill {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundColor(Ink.faint).help("Drag to reorder")
                Button { market.toggleWatch(t.id) } label: {
                    Image(systemName: market.watchlist.contains(t.id) ? "star.fill" : "star").font(.system(size: 10)).foregroundColor(Ink.amber)
                }.buttonStyle(.plain)
                Text(t.sym).font(.system(size: 12.5, weight: .semibold))
                Text("vol \(Fmt.usdCompact(t.vol24h))").font(.system(size: 10.5)).foregroundColor(Ink.faint)
            }
        } right: {
            Text("$\(Fmt.price(t.price))").font(.system(size: 12.5)).foregroundColor(Ink.dim)
            Text(Fmt.pct(t.change24h)).font(.system(size: 11.5, weight: .medium)).foregroundColor((t.change24h ?? 0) >= 0 ? Ink.green : Ink.red)
                .frame(width: 58, alignment: .trailing)
            Button { market.remove(t.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                .buttonStyle(.plain).foregroundColor(Ink.faint).help("Remove from Market")
        }
    }

    private func stockRow(_ s: StockRow) -> some View {
        RowPill {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundColor(Ink.faint).help("Drag to reorder")
                Button { market.toggleStockPin(s.id) } label: {
                    Image(systemName: market.stockPins.contains(s.id) ? "star.fill" : "star").font(.system(size: 10)).foregroundColor(Ink.amber)
                }.buttonStyle(.plain)
                Text(s.ticker).font(.system(size: 12.5, weight: .semibold))
                Text(s.chain == "base" ? "Base" : "Robinhood").font(.system(size: 10.5)).foregroundColor(Ink.faint)
                Text(s.isOpen ? "open" : s.session).font(.system(size: 10.5)).foregroundColor(Ink.faint)
            }
        } right: {
            Text("oracle $\(Fmt.price(s.oracle))").font(.system(size: 12)).foregroundColor(Ink.dim)
            Text(s.quarantined ? "DEX withheld" : Fmt.pct(s.drift)).font(.system(size: 11)).foregroundColor(Ink.faint)
                .frame(width: 70, alignment: .trailing)
            Button { market.removeStock(s.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                .buttonStyle(.plain).foregroundColor(Ink.faint).help("Remove from Market")
        }
    }

    private func isAddress(_ s: String) -> Bool { let t = s.trimmingCharacters(in: .whitespaces); return t.hasPrefix("0x") && t.count == 42 }

    private func run() {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard isAddress(t) else { return }
        checking = true; verdict = nil; checkError = nil
        Task {
            do { verdict = try await PreTradeVerdict.run(chain: "base", token: t) } catch { checkError = error.localizedDescription }
            checking = false
        }
    }
}

// MARK: Alerts

struct AlertsIslandView: View {
    @ObservedObject var alerts = AlertsStore.shared
    @ObservedObject var link = BlueAgentLink.shared
    @State private var token = ""
    @State private var kind = 0
    @State private var value = ""
    @State private var message: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: .brand)
            Group {
                if !link.isLinked { LinkFirst(what: "see your alerts") } else {
                    VStack(alignment: .leading, spacing: 7) {
                        CardTitle(title: "Alerts", sub: "\(alerts.watches.count) of 20 · checked every 5 min · free")
                        if link.canEditAlerts { form } else {
                            Text("This Mac can see alerts but not change them (Account → Change).").font(.system(size: 11)).foregroundColor(Ink.faint)
                        }
                        if let m = message { Text(m).font(.system(size: 11)).foregroundColor(Ink.amber) }
                        if let e = alerts.error { Text(e).font(.system(size: 11)).foregroundColor(Ink.amber) }
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 4) {
                                if alerts.watches.isEmpty { Text("No alerts yet. Ask in chat: \"alert me if ETH on Base drops 5% in 24h\".").font(.system(size: 12)).foregroundColor(Ink.dim) }
                                ForEach(alerts.watches) { w in row(w) }
                            }
                        }
                    }
                }
            }
            .padding(.leading, lead).padding(.trailing, 16).padding(.vertical, 12)
        }
        .padding(.bottom, 10)
        .onAppear { alerts.refresh() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                TextField("Token: ETH, AERO or a 0x address on Base", text: $token).textFieldStyle(.plain).font(.system(size: 12))
                    .onSubmit(lookUp).onChange(of: token) { _, _ in nowPrice = nil; scheduleLookUp() }
                if let p = nowPrice { Text("now $\(Fmt.price(p))").font(.system(size: 11)).foregroundColor(Ink.dim) }
                else if looking { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 6) {
                Picker("", selection: $kind) { Text("price ≥").tag(0); Text("price ≤").tag(1); Text("up % 24h").tag(2); Text("down % 24h").tag(3) }
                    .labelsHidden().frame(width: 110)
                    .onChange(of: kind) { _, _ in prefill() }
                TextField(kind < 2 ? "price in $" : "% move", text: $value)
                    .textFieldStyle(.plain).font(.system(size: 12)).frame(minWidth: 90).onSubmit(arm)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 10))
                if kind < 2, nowPrice != nil {
                    Button("Now") { prefill(force: true) }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Ink.accent)
                }
                Spacer(minLength: 0)
                Button(alerts.busy ? "…" : "Arm", action: arm).buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 5).background(Ink.text).foregroundColor(Color(hex: "#0B0C0E")).clipShape(Capsule())
                    .disabled(parsed == nil || alerts.busy || token.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(parsed == nil ? 0.45 : 1)
            }
        }
    }

    /// "2,500", "$2500", "5%" → a number; anything else → nil.
    private var parsed: Double? {
        let t = value.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let v = Double(t), v > 0 else { return nil }
        return v
    }

    @State private var nowPrice: Double?
    @State private var looking = false
    @State private var lookTask: Task<Void, Never>?

    private func scheduleLookUp() {
        lookTask?.cancel()
        lookTask = Task { try? await Task.sleep(nanoseconds: 600_000_000); if !Task.isCancelled { lookUp() } }
    }

    /// The current price, from Blue Agent: the base list for a symbol it
    /// carries, hub_token_price for an address. Unknown → no hint, never a guess.
    private func lookUp() {
        let t = token.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if let row = MarketStore.shared.allBase.first(where: { $0.sym.lowercased() == t.lowercased() || $0.id == t.lowercased() }), let p = row.price {
            nowPrice = p; prefill(); return
        }
        guard t.hasPrefix("0x"), t.count == 42 else { return }
        looking = true
        Task {
            let r = await MarketStore.price(t)
            looking = false
            if token.trimmingCharacters(in: .whitespaces) == t { nowPrice = r?.price; prefill() }
        }
    }

    private func prefill(force: Bool = false) {
        guard kind < 2, let p = nowPrice, force || value.isEmpty else { return }
        value = Fmt.price(p)
    }

    private func row(_ w: WatchRow) -> some View {
        RowPill {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(w.symbol) · \(w.chain)\(w.automation ? " · automation" : "")").font(.system(size: 12, weight: .semibold))
                Text(w.rule).font(.system(size: 11)).foregroundColor(Ink.dim).lineLimit(1)
            }
        } right: {
            if link.canEditAlerts {
                Toggle("", isOn: Binding(get: { w.active }, set: { alerts.setActive(w.id, $0) })).toggleStyle(.switch).labelsHidden().scaleEffect(0.6).frame(width: 34)
                Button { alerts.delete(w.id) } label: { Image(systemName: "trash").font(.system(size: 10.5)) }.buttonStyle(.plain).foregroundColor(Ink.red)
            } else if !w.active { Text("paused").font(.system(size: 10.5)).foregroundColor(Ink.faint) }
        }
    }

    private func arm() {
        guard let v = parsed else { return }
        var body: [String: Any] = ["chain": "base", "token": token.trimmingCharacters(in: .whitespaces), "threshold": v]
        switch kind {
        case 0: body["kind"] = "price"; body["direction"] = "above"
        case 1: body["kind"] = "price"; body["direction"] = "below"
        case 2: body["kind"] = "change"; body["direction"] = "up"; body["window"] = "24h"
        default: body["kind"] = "change"; body["direction"] = "down"; body["window"] = "24h"
        }
        Task { message = await alerts.create(body); if message == nil { value = ""; nowPrice = nil; token = "" } }
    }
}

// MARK: Activity

struct ActivityIslandView: View {
    @ObservedObject var feed = LiveFeed.shared
    @ObservedObject var link = BlueAgentLink.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: .brand)
            Group {
                if !link.isLinked { LinkFirst(what: "see your activity") } else {
                    VStack(alignment: .leading, spacing: 7) {
                        CardTitle(title: "Activity", sub: feed.lastRead.map { "read \($0.formatted(date: .omitted, time: .shortened))" })
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 4) {
                                if feed.items.isEmpty { Text(feed.lastRead == nil ? "Reading…" : "Nothing yet.").font(.system(size: 12)).foregroundColor(Ink.dim) }
                                ForEach(feed.items) { e in
                                    RowPill {
                                        HStack(spacing: 7) {
                                            Circle().fill(color(e.kind)).frame(width: 6, height: 6)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(LiveFeed.line(e)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                                if let d = e.detail { Text(d).font(.system(size: 11)).foregroundColor(Ink.dim).lineLimit(1) }
                                            }
                                        }
                                    } right: {
                                        Text(Date(timeIntervalSince1970: e.at / 1000).formatted(.relative(presentation: .numeric)))
                                            .font(.system(size: 10.5)).foregroundColor(Ink.faint)
                                        if let h = e.href {
                                            Button { BlueAgentLink.open(h) } label: { Image(systemName: "arrow.up.right.square").font(.system(size: 11)) }
                                                .buttonStyle(.plain).foregroundColor(Ink.dim).help("Explorer")
                                        }
                                    }
                                }
                            }
                        }
                        if let e = feed.lastError { Text(e).font(.system(size: 11)).foregroundColor(Ink.amber) }
                    }
                }
            }
            .padding(.leading, lead).padding(.trailing, 16).padding(.vertical, 12)
        }
        .padding(.bottom, 10)
        .onAppear { feed.refreshNow() }
    }

    private func color(_ k: String) -> Color {
        switch k { case "alert": Ink.accent; case "trade": Ink.green; case "blocked", "task_failed": Ink.red; default: Ink.faint }
    }
}

// MARK: Account (the ⚙︎ tab)

struct AccountIslandView: View {
    @ObservedObject var link = BlueAgentLink.shared
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: .brand)
            VStack(alignment: .leading, spacing: 7) {
                CardTitle(title: "Blue Agent wallet")
                walletBlock
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Toggle("", isOn: $state.soundEnabled).toggleStyle(.switch).labelsHidden().scaleEffect(0.6).frame(width: 34)
                    Text("Sound").font(.system(size: 11.5)).foregroundColor(Ink.dim)
                    Spacer()
                    Text("BlueBot never holds a key and cannot move funds.").font(.system(size: 10.5)).foregroundColor(Ink.faint)
                }
            }
            .padding(.leading, lead).padding(.trailing, 16).padding(.vertical, 12)
        }
        .padding(.bottom, 10)
        .onAppear { link.refresh() }
    }

    @ViewBuilder private var walletBlock: some View {
        switch link.status {
        case .unlinked:
            Text("Use the wallet you already have on blueagent.dev. Approve this Mac once on the web and choose what it may do.")
                .font(.system(size: 12)).foregroundColor(Ink.dim).fixedSize(horizontal: false, vertical: true)
            PrimaryButton("Link wallet") { link.beginLink() }
        case .requesting:
            ShimmeringText("Getting a code…").font(.system(size: 13))
        case .waiting(let code, let url, _):
            HStack(spacing: 12) {
                Text(code).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundColor(Ink.accent).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Approve this code on app.blueagent.dev/link").font(.system(size: 12))
                    ShimmeringText("Waiting for your wallet…").font(.system(size: 11))
                }
            }
            HStack(spacing: 8) {
                SecondaryButton("Open link page") { BlueAgentLink.open(url) }
                SecondaryButton("Cancel") { link.cancelLink() }
            }
        case .linked:
            RowPill {
                HStack(spacing: 6) {
                    Circle().fill(Ink.green).frame(width: 6, height: 6)
                    Text(link.wallet.map { BlueAgentLink.short($0) } ?? "Reading…").font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    Text("Base").font(.system(size: 10.5)).foregroundColor(Ink.faint)
                }
            } right: {
                Text("\(link.credits.map(String.init) ?? "…") credits").font(.system(size: 12)).foregroundColor(Ink.dim)
            }
            if let me = link.me {
                HStack(spacing: 6) {
                    scope(true, "Read")
                    scope(me.canChat, "Chat")
                    scope(me.canEditAlerts, "Alerts")
                    Spacer()
                    Button("Change") { link.relink() }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Ink.accent)
                    Button("Unlink") { link.unlink() }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Ink.red)
                }
            }
        case .failed(let m):
            Text(m).font(.system(size: 12)).foregroundColor(Ink.amber)
            SecondaryButton("Try again") { link.beginLink() }
        }
    }

    private func scope(_ on: Bool, _ t: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: on ? "checkmark" : "xmark").font(.system(size: 8, weight: .bold))
            Text(t).font(.system(size: 10.5, weight: .medium))
        }
        .foregroundColor(on ? Ink.green : Ink.faint)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background((on ? Ink.green : Color.white).opacity(0.08)).clipShape(Capsule())
    }
}

// MARK: Overview — market pulse pills

struct MarketPulseCard: View {
    @ObservedObject var state: AppState
    @ObservedObject var market = MarketStore.shared

    /// One pill: a Base token (24h change) or a pinned stock token (oracle price, its chain).
    struct Pill: Identifiable {
        let id: String; let label: String; let sub: String; let price: Double?; let change: Double?
        let focus: MarketStore.Focus
    }

    /// Pinned stock tokens and starred tokens first, then ETH and cbBTC, then
    /// the deepest-volume rest. Four at most.
    private var pills: [Pill] {
        var out: [Pill] = market.pinnedStocks.map { s in
            Pill(id: s.id, label: s.ticker, sub: s.chain == "base" ? "Base · oracle" : "RH · oracle", price: s.oracle, change: nil,
                 focus: .init(address: s.contract, symbol: s.ticker, chain: s.chain, pool: s.poolRef))
        }
        for t in picks where out.count < 4 {
            out.append(Pill(id: t.id, label: t.sym, sub: "", price: t.price, change: t.change24h, focus: .init(address: t.addr, symbol: t.sym)))
        }
        return Array(out.prefix(4))
    }

    private var picks: [BaseTokenRow] {
        let all = market.displayBase
        var out = all.filter { market.watchlist.contains($0.id) }
        for sym in ["ETH", "WETH", "cbBTC"] where out.count < 4 {
            if let t = all.first(where: { $0.sym == sym }), !out.contains(t) { out.append(t) }
        }
        for t in all.sorted(by: { ($0.vol24h ?? 0) > ($1.vol24h ?? 0) }) where out.count < 4 && !out.contains(t) { out.append(t) }
        return Array(out.prefix(4))
    }

    var body: some View {
        CardBackground(wash: .brand) {
            if pills.isEmpty {
                Text(market.error ?? "Reading prices…").font(.system(size: 12)).foregroundColor(Ink.dim)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(pills) { pill($0) }
                    }
                    Text("★ in Market to pin tokens and stocks here").font(.system(size: 9.5)).foregroundColor(Ink.faint)
                }
                .padding(10)
            }
        }
        .onAppear { if market.allBase.isEmpty { market.refresh() } }
    }

    private func pill(_ t: Pill) -> some View {
        let up = (t.change ?? 0) >= 0
        let c = t.change == nil ? Ink.dim : (up ? Ink.green : Ink.red)
        return Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { market.focus = t.focus; state.view = .market } } label: {
            HStack(spacing: 5) {
                Text(t.label).font(.system(size: 12, weight: .semibold)).foregroundColor(Ink.accent)
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("$\(Fmt.price(t.price))").font(.system(size: 11, weight: .medium)).foregroundColor(Ink.text)
                    Text(t.change == nil ? t.sub : Fmt.pct(t.change)).font(.system(size: 9.5, weight: .medium)).foregroundColor(t.change == nil ? Ink.faint : c)
                }
            }
            .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 34)
            .background(Capsule().fill(Ink.accent.opacity(0.08)))
            .overlay(Capsule().stroke(Ink.accent.opacity(0.32), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Overview — latest activity (static: a past event is not "in progress")

struct RecentActivityList: View {
    @ObservedObject var feed = LiveFeed.shared
    @ObservedObject var link = BlueAgentLink.shared
    private static let window: Double = 24 * 3600 * 1000

    private var recent: [LiveEvent] {
        let now = Date().timeIntervalSince1970 * 1000
        return Array(feed.items.filter { now - $0.at < Self.window }.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !link.isLinked {
                Text("Link your Blue Agent wallet (👤) to see alerts and activity.").font(.system(size: 12)).foregroundColor(Ink.dim)
            } else if recent.isEmpty {
                Text(feed.lastRead == nil ? "Reading your activity…" : "No new activity in the last 24h.").font(.system(size: 12)).foregroundColor(Ink.dim)
            } else {
                ForEach(recent) { e in
                    HStack(spacing: 6) {
                        Circle().fill(dot(e.kind)).frame(width: 5, height: 5)
                        Text(LiveFeed.line(e)).font(.system(size: 12, weight: .medium)).foregroundColor(Ink.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Date(timeIntervalSince1970: e.at / 1000).formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                            .font(.system(size: 10.5)).foregroundColor(Ink.faint).fixedSize()
                    }
                }
            }
        }
    }

    private func dot(_ k: String) -> Color {
        switch k { case "alert": Ink.accent; case "trade": Ink.green; case "blocked", "task_failed": Ink.red; default: Ink.faint }
    }
}

// MARK: Chat — a list result as rows

struct DiscoveryTableView: View {
    let table: DiscoveryTable
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(table.title.uppercased()).font(.system(size: 9.5, weight: .bold)).foregroundColor(Ink.faint)
            if table.rows.isEmpty { Text(table.note ?? "Nothing to show.").font(.system(size: 11.5)).foregroundColor(Ink.dim) }
            ForEach(table.rows) { r in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(r.symbol).font(.system(size: 12, weight: .semibold)).foregroundColor(Ink.accent)
                        Text(r.chain).font(.system(size: 10)).foregroundColor(Ink.faint)
                        if let w = r.warning { Text(w).font(.system(size: 10, weight: .semibold)).foregroundColor(Ink.red) }
                    }
                    if !r.facts.isEmpty {
                        Text(r.facts.joined(separator: " · ")).font(.system(size: 10.5)).foregroundColor(Ink.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Ink.row).clipShape(RoundedRectangle(cornerRadius: 9))
            }
            if table.more > 0 { Text("+\(table.more) more").font(.system(size: 10.5)).foregroundColor(Ink.faint) }
            if let n = table.note, !table.rows.isEmpty { Text(n).font(.system(size: 10.5)).foregroundColor(Ink.faint) }
            Text("Trading is in Blue Chat for now.").font(.system(size: 10)).foregroundColor(Ink.faint)
        }
    }
}

// MARK: Island event card

struct IslandEventCard: View {
    @ObservedObject var feed = LiveFeed.shared
    let refused: Bool

    var body: some View {
        ZStack {
            CardBackground(wash: refused ? .red : .cyan)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Circle().fill(Ink.accent).frame(width: 8, height: 8)
                    Text("Blue Agent").font(.system(size: 12, weight: .semibold)).foregroundColor(Ink.text)
                    Text(feed.current?.title ?? "").font(.system(size: 12)).foregroundColor(Ink.dim)
                }
                Text(feed.current?.detail ?? feed.current?.title ?? "").font(.system(size: 14, weight: .semibold)).lineLimit(3)
                HStack(spacing: 8) {
                    PrimaryButton("See activity") { AppState.shared.view = .activity; feed.dismiss() }
                    SecondaryButton("OK") { feed.dismiss(); NotificationCenter.default.post(name: .islandCollapse, object: nil) }
                }
                Text(refused ? "Blocked on evidence by Blue Agent's pre-trade check." : "Nothing trades on its own. Trades are signed by your wallet in Blue Chat.")
                    .font(.system(size: 10.5)).foregroundColor(Color(hex: "#6B7079"))
            }
            .padding(.leading, 116).padding(.trailing, 16).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Market — drag to reorder

private struct RowDrop: DropDelegate {
    let target: String
    @Binding var dragging: String?
    let move: (String, String) -> Void
    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target else { return }
        withAnimation(.easeInOut(duration: 0.15)) { move(d, target) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

// MARK: Market — one token's chart

struct TokenChartView: View {
    let focus: MarketStore.Focus
    @ObservedObject var market = MarketStore.shared
    @State private var tf = "1d"
    @State private var series: [(t: Date, v: Double)] = []
    @State private var loading = false

    private var first: Double? { series.first?.v }
    private var last: Double? { series.last?.v }
    /// The move over the chart's own window, computed here from the series.
    private var change: Double? { guard let a = first, let b = last, a > 0 else { return nil }; return (b / a - 1) * 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { withAnimation(.easeInOut(duration: 0.18)) { market.focus = nil } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                }.buttonStyle(.plain).foregroundColor(Ink.dim)
                Text(focus.symbol).font(.system(size: 15, weight: .semibold))
                Text(focus.chain == "base" ? "Base" : "Robinhood Chain").font(.system(size: 10.5)).foregroundColor(Ink.faint)
                if let l = last { Text("$\(Fmt.price(l))").font(.system(size: 13, weight: .medium)).foregroundColor(Ink.text) }
                if let c = change {
                    Text("\(Fmt.pct(c)) \(label(tf))").font(.system(size: 11, weight: .medium)).foregroundColor(c >= 0 ? Ink.green : Ink.red)
                }
                Spacer()
                ForEach(["1d", "7d", "30d"], id: \.self) { t in
                    Button(label(t)) { tf = t; load() }
                        .buttonStyle(.plain).font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .foregroundColor(tf == t ? Ink.accent : Ink.faint)
                        .background(Capsule().fill(tf == t ? Ink.accent.opacity(0.14) : .clear))
                }
            }
            ZStack {
                if series.count >= 2 {
                    let lo = series.map(\.v).min() ?? 0, hi = series.map(\.v).max() ?? 1
                    let pad = max((hi - lo) * 0.08, hi * 0.001)
                    let up = (change ?? 0) >= 0
                    Chart(series, id: \.t) { p in
                        AreaMark(x: .value("t", p.t), yStart: .value("lo", lo - pad), yEnd: .value("v", p.v))
                            .foregroundStyle(LinearGradient(colors: [(up ? Ink.green : Ink.red).opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("t", p.t), y: .value("v", p.v))
                            .foregroundStyle(up ? Ink.green : Ink.red)
                            .lineStyle(StrokeStyle(lineWidth: 1.6))
                    }
                    .chartYScale(domain: (lo - pad)...(hi + pad))
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                            AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                            AxisValueLabel { if let d = v.as(Double.self) { Text("$\(Fmt.price(d))").font(.system(size: 9)).foregroundColor(Ink.faint) } }
                        }
                    }
                } else if loading {
                    ShimmeringText("Reading \(focus.symbol) price history…").font(.system(size: 12))
                } else {
                    Text("No chart for this token yet.").font(.system(size: 12)).foregroundColor(Ink.dim)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 14) {
                Spacer()
                let stockId = "\(focus.chain):\(focus.address.lowercased())"
                let isStock = focus.pool != nil || market.stocks.contains { $0.id == stockId }
                let pinned = isStock ? market.stockPins.contains(stockId) : market.isPinned(focus.address)
                Button { if isStock { market.toggleStockPin(stockId) } else { market.toggleWatch(focus.address.lowercased()) } } label: {
                    Label(pinned ? "Pinned" : "Pin", systemImage: pinned ? "star.fill" : "star").font(.system(size: 10.5, weight: .semibold))
                }.buttonStyle(.plain).foregroundColor(Ink.amber)
                Button { ChatEngine.shared.send("analyze \(focus.symbol) on \(focus.chain == "base" ? "Base" : "Robinhood Chain") (\(focus.address)): price, liquidity, tax and risk"); AppState.shared.view = .prompt } label: {
                    Label("Ask Blue Agent", systemImage: "bubble.left").font(.system(size: 10.5, weight: .semibold))
                }.buttonStyle(.plain).foregroundColor(Ink.accent)
            }
        }
        .onAppear(perform: load)
        .onChange(of: focus) { _, _ in load() }
    }

    private func label(_ t: String) -> String { t == "1d" ? "24H" : t.uppercased() }

    private func load() {
        loading = true
        let addr = focus.address, want = tf
        Task {
            defer { loading = false }
            let poolQ = focus.pool.map { "&pool=\($0)" } ?? ""
            guard let data = try? await MarketStore.fetch("/api/token-ohlcv?chain=\(focus.chain)&token=\(addr)\(poolQ)&tf=\(want)"),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { series = []; return }
            guard want == tf, addr == focus.address else { return }
            let rows = (j["series"] as? [[Any]] ?? []).compactMap { r -> (t: Date, v: Double)? in
                guard r.count == 2, let t = (r[0] as? NSNumber)?.doubleValue, let v = (r[1] as? NSNumber)?.doubleValue else { return nil }
                return (t: Date(timeIntervalSince1970: t), v: v)
            }
            series = rows
        }
    }
}
