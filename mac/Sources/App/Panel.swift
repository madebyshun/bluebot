import AppKit
import SwiftUI

// MARK: - BlueBot panel
//
// Blue Agent, slimmed down for the Mac, on the wallet you already use there:
//   Chat · Market · Alerts · Activity · Account
// Trading is not in BlueBot yet (it needs the wallet to sign); a trade Blue
// Agent prepares in chat is named and opens in Blue Chat.
// A floating window that drops from the notch (or the top of the screen). The
// island stays the place alerts appear; its buttons open this panel.

enum PanelTab: String, CaseIterable, Identifiable {
    case chat = "Chat", market = "Market", alerts = "Alerts", activity = "Activity", account = "Account"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right.fill"
        case .market: "chart.line.uptrend.xyaxis"
        case .alerts: "bell.fill"
        case .activity: "list.bullet.rectangle"
        case .account: "person.crop.circle"
        }
    }
}

@MainActor
final class PanelController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = PanelController()
    @Published var tab: PanelTab = .chat
    private var window: NSPanel?

    func show(_ tab: PanelTab? = nil) {
        if let tab { self.tab = tab }
        if AppState.shared.mode == .expanded { NotificationCenter.default.post(name: .islandCollapse, object: nil) }
        if window == nil {
            let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 640),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
                            backing: .buffered, defer: false)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.level = .floating
            w.hidesOnDeactivate = false
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.contentMinSize = NSSize(width: 400, height: 480)
            w.contentView = NSHostingView(rootView: PanelRoot())
            w.backgroundColor = NSColor(cgColor: BlueAgentBrand.bg)
            w.delegate = self
            window = w
            place(w)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggle() { if window?.isVisible == true { window?.orderOut(nil) } else { show() } }

    private func place(_ w: NSWindow) {
        guard let screen = IslandWindowController.notchScreen() ?? NSScreen.main else { w.center(); return }
        let v = screen.visibleFrame
        let size = w.frame.size
        w.setFrameOrigin(NSPoint(x: v.midX - size.width / 2, y: v.maxY - size.height - 8))
    }
}

// MARK: Palette

enum BB {
    static let bg = Color(cgColor: BlueAgentBrand.bg)
    static let surface = Color(cgColor: BlueAgentBrand.surface)
    static let line = Color(cgColor: BlueAgentBrand.border)
    static let accent = Color(cgColor: BlueAgentBrand.accent)
    static let ink = Color(hex: "#F5F6F8")
    static let dim = Color(hex: "#8E939C")
    static let faint = Color(hex: "#5A6178")
    static let green = Color(hex: "#34D399")
    static let red = Color(hex: "#F87171")
    static let amber = Color(hex: "#F59E0B")
    static func mono(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w, design: .monospaced) }
}

struct BBCard<C: View>: View {
    var accent: Color? = nil
    @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(BB.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent?.opacity(0.45) ?? BB.line, lineWidth: 1))
    }
}

struct BBButton: View {
    let title: String; var primary = true; var disabled = false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(BB.mono(12, .bold)).padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundColor(primary ? Color(cgColor: BlueAgentBrand.bg) : BB.accent)
                .background(RoundedRectangle(cornerRadius: 8).fill(primary ? BB.accent : BB.accent.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(BB.accent.opacity(primary ? 0 : 0.4), lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1)
    }
}

// MARK: Root

struct PanelRoot: View {
    @ObservedObject var panel = PanelController.shared
    @ObservedObject var link = BlueAgentLink.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            Divider().overlay(BB.line)
            Group {
                switch panel.tab {
                case .chat: ChatPane()
                case .market: MarketPane()
                case .alerts: AlertsPane()
                case .activity: ActivityPane()
                case .account: AccountPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BB.bg)
        .foregroundColor(BB.ink)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text("BlueBot").font(.system(size: 14, weight: .bold))
                Text("built on Blue Agent").font(BB.mono(10)).foregroundColor(BB.accent)
            }
            Spacer()
            if let w = link.wallet {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(BlueAgentLink.short(w)).font(BB.mono(11, .semibold))
                    Text(link.credits.map { "\($0) credits" } ?? "credits …").font(BB.mono(10)).foregroundColor(BB.dim)
                }
                .onTapGesture { panel.tab = .account }
            } else {
                BBButton(title: "Link wallet", primary: false) { panel.tab = .account }
            }
        }
        .padding(.horizontal, 14).padding(.top, 26).padding(.bottom, 8)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases) { t in
                Button { panel.tab = t } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 13))
                        Text(t.rawValue).font(BB.mono(9.5, .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .foregroundColor(panel.tab == t ? BB.accent : BB.dim)
                    .background(RoundedRectangle(cornerRadius: 8).fill(panel.tab == t ? BB.accent.opacity(0.10) : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 8)
    }
}

// MARK: Link prompt

struct LinkNeeded: View {
    let what: String
    var body: some View {
        VStack(spacing: 10) {
            Text("Link your Blue Agent wallet to \(what)").font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center)
            Text("Use the wallet you already have on blueagent.dev. No new wallet, and BlueBot never holds a key.")
                .font(.system(size: 12)).foregroundColor(BB.dim).multilineTextAlignment(.center)
            BBButton(title: "Link wallet") { PanelController.shared.tab = .account }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Account

struct AccountPane: View {
    @ObservedObject var link = BlueAgentLink.shared
    @ObservedObject var state = AppState.shared
    @State private var apiBase = UserDefaults.standard.string(forKey: "apiBase") ?? ""
    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BBCard(accent: link.isLinked ? BB.green : nil) { wallet }
                if link.isLinked, let me = link.me { BBCard { permissions(me) } }
                BBCard {
                    Text("GENERAL").font(BB.mono(10, .bold)).foregroundColor(BB.dim)
                    Toggle("Sounds", isOn: $state.soundEnabled).font(.system(size: 12))
                }
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) { advanced }.font(.system(size: 12))
                Text("BlueBot never holds a key and cannot sign or move funds. Chat spends your wallet's Blue Agent credits, never more per day than you allowed this Mac.")
                    .font(.system(size: 11)).foregroundColor(BB.faint)
            }
            .padding(14)
        }
        .onAppear { link.refresh() }
    }

    @ViewBuilder private var wallet: some View {
        Text("BLUE AGENT WALLET").font(BB.mono(10, .bold)).foregroundColor(BB.dim)
        switch link.status {
        case .unlinked:
            Text("Link the wallet you use on blueagent.dev. You approve it once on the web and choose what BlueBot may do.")
                .font(.system(size: 12))
            BBButton(title: "Link wallet") { link.beginLink() }
        case .requesting:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Getting a code…").font(.system(size: 12)) }
        case .waiting(let code, let url, _):
            Text("Approve this code at app.blueagent.dev/link (opened in your browser):").font(.system(size: 12))
            Text(code).font(BB.mono(24, .bold)).foregroundColor(BB.accent).textSelection(.enabled)
            HStack { BBButton(title: "Open link page", primary: false) { BlueAgentLink.open(url) }; Button("Cancel") { link.cancelLink() } }
        case .linked(let device):
            HStack(spacing: 8) {
                Circle().fill(BB.green).frame(width: 8, height: 8)
                Text(link.wallet ?? "Reading…").font(BB.mono(11, .semibold)).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            }
            Text("Credits: \(link.credits.map(String.init) ?? "…") (daily free left: \(link.dailyRemaining.map(String.init) ?? "…"))")
                .font(BB.mono(11)).foregroundColor(BB.dim)
            Text("Base 8453 · the same wallet as on Blue Chat\(device.map { " · \($0)" } ?? "")").font(BB.mono(10)).foregroundColor(BB.faint)
            BBButton(title: "Unlink this Mac", primary: false) { link.unlink() }
        case .failed(let m):
            Text(m).font(.system(size: 12)).foregroundColor(BB.amber)
            BBButton(title: "Try again", primary: false) { link.beginLink() }
        }
    }

    @ViewBuilder private func permissions(_ me: BlueAgentAPI.Me) -> some View {
        Text("WHAT THIS MAC MAY DO").font(BB.mono(10, .bold)).foregroundColor(BB.dim)
        row(true, "See alerts and activity")
        if let c = me.chat, me.canChat {
            row(true, "Chat: \(c.spent.map(String.init) ?? "…") of \(c.cap) credits used today")
        } else {
            row(false, "Chat with Blue Agent")
        }
        row(me.canEditAlerts, "Set and change price alerts")
        HStack {
            BBButton(title: "Change", primary: false) { link.relink() }
            Text("Links again so you can choose on the web.").font(.system(size: 10.5)).foregroundColor(BB.faint)
        }
    }

    private func row(_ on: Bool, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle").foregroundColor(on ? BB.green : BB.faint)
            Text(text).font(.system(size: 12)).foregroundColor(on ? BB.ink : BB.dim)
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Blue Agent server (empty = \(BlueAgentAPI.defaultBase))").font(.system(size: 11)).foregroundColor(BB.dim)
            HStack {
                TextField(BlueAgentAPI.defaultBase, text: $apiBase).textFieldStyle(.roundedBorder).font(BB.mono(11))
                Button("Save") { UserDefaults.standard.set(apiBase, forKey: "apiBase"); link.refresh() }
            }
            Text("A link belongs to one server: after changing it, link again.").font(.system(size: 10.5)).foregroundColor(BB.faint)
        }
        .padding(.top, 6)
    }
}

// MARK: Chat

struct ChatPane: View {
    @ObservedObject var chat = ChatEngine.shared
    @ObservedObject var link = BlueAgentLink.shared
    @State private var input = ""

    var body: some View {
        if !link.isLinked { LinkNeeded(what: "chat") }
        else if link.me != nil && !link.canChat { LinkNeeded(what: "chat (allow chat when linking)") }
        else {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if chat.messages.isEmpty { suggestions }
                            ForEach(chat.messages) { m in bubble(m).id(m.id) }
                        }
                        .padding(14)
                    }
                    .onChange(of: chat.messages.last?.text) { _, _ in if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                }
                composer
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask Blue Agent").font(.system(size: 13, weight: .semibold))
            ForEach(["what's trending on Base?", "what launched in the last hour on Robinhood Chain?", "is 0x… on Base safe to buy?",
                     "alert me if ETH on Base drops 5% in 24h"], id: \.self) { s in
                Button { chat.send(s) } label: {
                    Text("> \(s)").font(BB.mono(11.5)).foregroundColor(BB.ink).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(BB.surface)).overlay(RoundedRectangle(cornerRadius: 8).stroke(BB.line))
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func bubble(_ m: BAChatMessage) -> some View {
        if m.role == "user" {
            HStack { Spacer(minLength: 40)
                Text(m.text).font(.system(size: 13)).padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(BB.accent.opacity(0.18)))
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !m.tools.isEmpty {
                    Text(m.tools.map { "⚙︎ \($0)" }.joined(separator: "  ")).font(BB.mono(10)).foregroundColor(BB.dim)
                }
                if !m.text.isEmpty {
                    Text(LocalizedStringKey(m.text)).font(.system(size: 13)).textSelection(.enabled)
                } else if chat.streaming && m.id == chat.messages.last?.id && m.cards.isEmpty {
                    ProgressView().controlSize(.small)
                }
                ForEach(Array(m.cards.enumerated()), id: \.offset) { _, c in card(c) }
                if let n = m.notice { Text(n).font(.system(size: 12)).foregroundColor(BB.amber) }
            }
        }
    }

    @ViewBuilder private func card(_ c: ChatCard) -> some View {
        switch c {
        case .alert(let d): AlertDraftCard(draft: d)
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            HStack {
                Picker("", selection: $chat.preset) {
                    ForEach(ChatPreset.all) { p in Text("\(p.label) · \(p.credits) cr").tag(p.id) }
                }
                .labelsHidden().frame(width: 150)
                Spacer()
                if !chat.messages.isEmpty { Button("New chat") { chat.clear() }.buttonStyle(.link).font(.system(size: 11)) }
            }
            HStack(spacing: 8) {
                TextField("Ask Blue Agent…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...5)
                    .padding(9).background(RoundedRectangle(cornerRadius: 10).fill(BB.surface)).overlay(RoundedRectangle(cornerRadius: 10).stroke(BB.line))
                    .onSubmit(send)
                if chat.streaming { BBButton(title: "Stop", primary: false) { chat.stop() } }
                else { BBButton(title: "Send", disabled: input.trimmingCharacters(in: .whitespaces).isEmpty, action: send) }
            }
        }
        .padding(12).background(BB.bg)
    }

    private func send() { let t = input; input = ""; chat.send(t) }
}

struct AlertDraftCard: View {
    let draft: AlertDraft
    @ObservedObject var alerts = AlertsStore.shared
    @State private var result: String?
    @State private var armed = false

    var body: some View {
        BBCard(accent: armed ? BB.green : BB.amber) {
            Text(draft.automation ? "⚙︎ AUTOMATION · checked every 5 min · free" : "🔔 PRICE ALERT · checked every 5 min · free")
                .font(BB.mono(10, .bold)).foregroundColor(BB.dim)
            Text(draft.rule.prefix(1).uppercased() + draft.rule.dropFirst() + ".").font(.system(size: 13, weight: .semibold))
            if let p = draft.priceNow { Text("Now: $\(Fmt.price(p))").font(BB.mono(11)).foregroundColor(BB.dim) }
            if draft.automation {
                Text("When it fires, the trade is prepared in Blue Chat for your wallet to review. Nothing executes on its own.").font(.system(size: 11)).foregroundColor(BB.dim)
            }
            if armed { Text("Armed.").font(BB.mono(12, .bold)).foregroundColor(BB.green) }
            else {
                BBButton(title: alerts.busy ? "Arming…" : (draft.automation ? "Arm automation" : "Arm alert"), disabled: alerts.busy) {
                    Task {
                        let err = await alerts.create(draft.body.mapValues(\.any))
                        if let err { result = err } else { armed = true }
                    }
                }
            }
            if let r = result { Text(r).font(.system(size: 11)).foregroundColor(BB.amber) }
        }
    }
}

// MARK: Market

struct MarketPane: View {
    @ObservedObject var market = MarketStore.shared
    @State private var segment = 0
    @State private var checkInput = ""
    @State private var check: PreTradeVerdict?
    @State private var checking = false
    @State private var checkError: String?

    var body: some View {
        VStack(spacing: 0) {
            checkBar
            Picker("", selection: $segment) { Text("Base tokens").tag(0); Text("Stock tokens").tag(1) }
                .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 14).padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 6) {
                    if segment == 0 { ForEach(market.baseTokens) { baseRow($0) } }
                    else { ForEach(market.stocks) { stockRow($0) } }
                    footer
                }
                .padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .onAppear { market.refresh(); suggestClipboard() }
    }

    private var checkBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Check a token: paste a 0x address on Base", text: $checkInput)
                    .textFieldStyle(.roundedBorder).font(BB.mono(11)).onSubmit(runCheck)
                BBButton(title: checking ? "…" : "Check", disabled: checking || !isAddress(checkInput), action: runCheck)
            }
            if let c = check { VerdictView(check: c) }
            if let e = checkError { Text(e).font(.system(size: 11)).foregroundColor(BB.amber) }
        }
        .padding(14)
    }

    private func isAddress(_ s: String) -> Bool { let t = s.trimmingCharacters(in: .whitespaces); return t.hasPrefix("0x") && t.count == 42 }

    private func runCheck() {
        let t = checkInput.trimmingCharacters(in: .whitespaces)
        guard isAddress(t) else { return }
        checking = true; checkError = nil; check = nil
        Task {
            do { check = try await PreTradeVerdict.run(chain: "base", token: t) }
            catch { checkError = error.localizedDescription }
            checking = false
        }
    }

    private func suggestClipboard() {
        if checkInput.isEmpty, let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), isAddress(s) { checkInput = s }
    }

    private func baseRow(_ t: BaseTokenRow) -> some View {
        HStack(spacing: 10) {
            Button { market.toggleWatch(t.id) } label: { Image(systemName: market.watchlist.contains(t.id) ? "star.fill" : "star").foregroundColor(BB.amber) }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.sym).font(.system(size: 13, weight: .semibold))
                Text("Base · vol \(Fmt.usdCompact(t.vol24h))").font(BB.mono(10)).foregroundColor(BB.faint)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("$\(Fmt.price(t.price))").font(BB.mono(12, .semibold))
                Text(Fmt.pct(t.change24h)).font(BB.mono(11)).foregroundColor((t.change24h ?? 0) >= 0 ? BB.green : BB.red)
            }
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(BB.surface))
    }

    private func stockRow(_ s: StockRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(s.ticker).font(.system(size: 13, weight: .semibold))
                Text("\(s.chain == "base" ? "Base · B20" : "Robinhood Chain") · \(s.isOpen ? "market open" : s.session)").font(BB.mono(10)).foregroundColor(BB.faint)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("oracle $\(Fmt.price(s.oracle))").font(BB.mono(11, .semibold))
                Text(s.quarantined ? "DEX withheld" : "DEX $\(Fmt.price(s.dex)) · \(Fmt.pct(s.drift))").font(BB.mono(10)).foregroundColor(BB.dim)
            }
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(BB.surface))
    }

    private var footer: some View {
        Text(segment == 0 ? "Prices: DexScreener, deepest Base pool · Blue Agent /api/base-tokens" :
                "Oracle: Chainlink · DEX: the token's pool · Blue Agent /api/hood/snapshot. Stock tokens are not shares.")
            .font(BB.mono(9.5)).foregroundColor(BB.faint).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
    }
}

struct VerdictView: View {
    let check: PreTradeVerdict
    var color: Color { check.verdict == "BLOCK" ? BB.red : check.verdict == "WARN" ? BB.amber : BB.green }
    var body: some View {
        BBCard(accent: color) {
            HStack {
                Text(check.verdict).font(BB.mono(12, .heavy)).foregroundColor(Color(cgColor: BlueAgentBrand.bg))
                    .padding(.horizontal, 8).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 6).fill(color))
                Text(check.label).font(BB.mono(11, .semibold)).lineLimit(1)
                Spacer()
            }
            if check.reasons.isEmpty { Text("Nothing measured against it.").font(.system(size: 11.5)).foregroundColor(BB.dim) }
            ForEach(Array(check.reasons.enumerated()), id: \.offset) { _, r in
                Text("• \(r.text)").font(.system(size: 11.5)).foregroundColor(r.level == "INFO" ? BB.dim : color)
            }
            Text("Blue Agent pre-trade check · verdict decided in code").font(BB.mono(9.5)).foregroundColor(BB.faint)
        }
    }
}

// MARK: Alerts

struct AlertsPane: View {
    @ObservedObject var alerts = AlertsStore.shared
    @ObservedObject var link = BlueAgentLink.shared
    @State private var token = "ETH"
    @State private var kind = 0          // 0 above, 1 below, 2 up %, 3 down %
    @State private var value = ""
    @State private var message: String?

    var body: some View {
        if !link.isLinked { LinkNeeded(what: "see your alerts") } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !link.canEditAlerts {
                        Text("This Mac can see your alerts but not change them. To set alerts here, Account → Change, and allow alerts.")
                            .font(.system(size: 11.5)).foregroundColor(BB.dim)
                    } else { BBCard {
                        Text("NEW ALERT · BASE · checked every 5 min · free").font(BB.mono(10, .bold)).foregroundColor(BB.dim)
                        HStack {
                            TextField("ETH, USDC or 0x…", text: $token).textFieldStyle(.roundedBorder).font(BB.mono(12)).frame(width: 130)
                            Picker("", selection: $kind) { Text("price ≥").tag(0); Text("price ≤").tag(1); Text("up %").tag(2); Text("down %").tag(3) }.labelsHidden()
                            TextField(kind < 2 ? "$" : "%", text: $value).textFieldStyle(.roundedBorder).font(BB.mono(12))
                        }
                        BBButton(title: "Arm alert", disabled: Double(value) == nil || alerts.busy) { arm() }
                        if let m = message { Text(m).font(.system(size: 11)).foregroundColor(BB.amber) }
                        Text("Or just ask in Chat: \"alert me if ETH on Base drops 5% in 24h\".")
                            .font(.system(size: 10.5)).foregroundColor(BB.faint)
                    } }
                    Text("YOUR ALERTS (\(alerts.watches.count) of 20)").font(BB.mono(10, .bold)).foregroundColor(BB.dim)
                    if alerts.watches.isEmpty { Text("No alerts yet.").font(.system(size: 12)).foregroundColor(BB.dim) }
                    ForEach(alerts.watches) { w in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(w.symbol) · \(w.chain)\(w.automation ? " · automation" : "")").font(.system(size: 12.5, weight: .semibold))
                                Text(w.rule).font(.system(size: 11.5)).foregroundColor(BB.dim)
                            }
                            Spacer()
                            if link.canEditAlerts {
                                Toggle("", isOn: Binding(get: { w.active }, set: { alerts.setActive(w.id, $0) })).toggleStyle(.switch).labelsHidden().scaleEffect(0.7)
                                Button { alerts.delete(w.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundColor(BB.red)
                            } else if !w.active {
                                Text("paused").font(BB.mono(10)).foregroundColor(BB.faint)
                            }
                        }
                        .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(BB.surface))
                    }
                    if let e = alerts.error { Text(e).font(.system(size: 11)).foregroundColor(BB.amber) }
                }
                .padding(14)
            }
            .onAppear { alerts.refresh() }
        }
    }

    private func arm() {
        guard let v = Double(value) else { return }
        var body: [String: Any] = ["chain": "base", "token": token.trimmingCharacters(in: .whitespaces), "threshold": v]
        switch kind {
        case 0: body["kind"] = "price"; body["direction"] = "above"
        case 1: body["kind"] = "price"; body["direction"] = "below"
        case 2: body["kind"] = "change"; body["direction"] = "up"; body["window"] = "24h"
        default: body["kind"] = "change"; body["direction"] = "down"; body["window"] = "24h"
        }
        Task { message = await alerts.create(body); if message == nil { value = "" } }
    }
}

// MARK: Activity

struct ActivityPane: View {
    @ObservedObject var feed = LiveFeed.shared
    @ObservedObject var link = BlueAgentLink.shared

    var body: some View {
        if !link.isLinked { LinkNeeded(what: "see your activity") } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("ACTIVITY").font(BB.mono(10, .bold)).foregroundColor(BB.dim)
                        Spacer()
                        Button("Refresh") { feed.refreshNow() }.buttonStyle(.link).font(.system(size: 11))
                    }
                    if feed.items.isEmpty { Text(feed.lastRead == nil ? "Reading…" : "Nothing yet.").font(.system(size: 12)).foregroundColor(BB.dim) }
                    ForEach(feed.items) { e in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(color(e.kind)).frame(width: 7, height: 7).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LiveFeed.line(e)).font(.system(size: 12.5, weight: .semibold))
                                if let d = e.detail { Text(d).font(.system(size: 11.5)).foregroundColor(BB.dim) }
                                HStack(spacing: 8) {
                                    Text(Date(timeIntervalSince1970: e.at / 1000).formatted(date: .abbreviated, time: .shortened)).font(BB.mono(10)).foregroundColor(BB.faint)
                                    if let h = e.href { Button("Explorer") { BlueAgentLink.open(h) }.buttonStyle(.link).font(.system(size: 11)) }
                                }
                            }
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 10).fill(BB.surface))
                    }
                    if let e = feed.lastError { Text(e).font(.system(size: 11)).foregroundColor(BB.amber) }
                }
                .padding(14)
            }
        }
    }

    private func color(_ k: String) -> Color {
        switch k { case "alert": BB.accent; case "trade": BB.green; case "blocked", "task_failed": BB.red; default: BB.dim }
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
                    Circle().fill(BB.accent).frame(width: 8, height: 8)
                    Text("Blue Agent").font(.system(size: 12, weight: .semibold)).foregroundColor(BB.ink)
                    Text(feed.current?.title ?? "").font(.system(size: 12)).foregroundColor(BB.dim)
                }
                Text(feed.current?.detail ?? feed.current?.title ?? "").font(.system(size: 14, weight: .semibold)).lineLimit(3)
                HStack(spacing: 8) {
                    PrimaryButton("Open BlueBot") { PanelController.shared.show(.activity); feed.dismiss() }
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
