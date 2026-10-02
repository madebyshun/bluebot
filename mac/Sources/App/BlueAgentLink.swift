import AppKit
import SwiftUI

// MARK: - Link to your Blue Agent wallet (device code)
//
// BlueBot uses the wallet you already have on blueagent.dev — it never makes
// one and never holds a key. You approve this Mac once on
// app.blueagent.dev/link and choose what it may do there: read (always), chat
// on your credits up to a daily limit, and set or change alerts. The token
// that comes back lives in the Keychain; `me` is what the server says it may
// do, refreshed on launch and after every chat.

@MainActor
final class BlueAgentLink: ObservableObject {
    static let shared = BlueAgentLink()

    enum Status: Equatable {
        case unlinked
        case requesting
        case waiting(code: String, url: String, expires: Date)
        case linked(device: String?)
        case failed(String)
    }

    @Published private(set) var status: Status = .unlinked
    @Published private(set) var me: BlueAgentAPI.Me?
    @Published private(set) var credits: Int?
    @Published private(set) var dailyRemaining: Int?
    private var linkTask: Task<Void, Never>?
    private static let deviceKey = "blueagentDevice"

    private init() {
        if BlueAgentAPI.token != nil { status = .linked(device: UserDefaults.standard.string(forKey: Self.deviceKey)) }
    }

    var isLinked: Bool { if case .linked = status { return true } else { return false } }
    var wallet: String? { me?.wallet }
    var canChat: Bool { me?.canChat ?? false }
    var canEditAlerts: Bool { me?.canEditAlerts ?? false }

    /// Re-reads what this link may do, and the wallet's credits. An unlinked
    /// answer (the link was removed on the web) forgets the token.
    func refresh() {
        guard BlueAgentAPI.token != nil else { me = nil; return }
        Task {
            do {
                let m = try await BlueAgentAPI.me()
                me = m
                let (c, d) = await BlueAgentAPI.credits(wallet: m.wallet)
                credits = c; dailyRemaining = d
            } catch BlueAgentAPI.Failure.unlinked {
                KeychainStore.shared.remove(BlueAgentAPI.tokenKey)
                me = nil; status = .unlinked
            } catch { /* offline: keep what we had */ }
        }
    }

    func beginLink() {
        linkTask?.cancel()
        status = .requesting
        let name = "\(Host.current().localizedName ?? "Mac") (BlueBot)"
        linkTask = Task { [weak self] in
            do {
                let code = try await BlueAgentAPI.requestCode(name: name)
                guard let self, !Task.isCancelled else { return }
                let expires = Date().addingTimeInterval(TimeInterval(code.expires_in))
                self.status = .waiting(code: code.user_code, url: code.verification_uri_complete, expires: expires)
                Self.open(code.verification_uri_complete)
                while !Task.isCancelled, Date() < expires {
                    try await Task.sleep(nanoseconds: UInt64(max(code.interval, 3)) * 1_000_000_000)
                    if let tok = try await BlueAgentAPI.pollToken(deviceCode: code.device_code) {
                        KeychainStore.shared.set(BlueAgentAPI.tokenKey, value: tok.access_token)
                        UserDefaults.standard.set(tok.device.name, forKey: Self.deviceKey)
                        self.status = .linked(device: tok.device.name)
                        self.refresh()
                        LiveFeed.shared.start()
                        AlertsStore.shared.refresh()
                        SoundEngine.shared.play("love")
                        return
                    }
                }
                if !Task.isCancelled { self.status = .failed(BlueAgentAPI.Failure.expired.localizedDescription) }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    func cancelLink() {
        linkTask?.cancel(); linkTask = nil
        status = BlueAgentAPI.token != nil ? .linked(device: UserDefaults.standard.string(forKey: Self.deviceKey)) : .unlinked
    }

    func unlink() {
        Task {
            await BlueAgentAPI.unlink()
            UserDefaults.standard.removeObject(forKey: Self.deviceKey)
            status = .unlinked; me = nil; credits = nil; dailyRemaining = nil
            ChatEngine.shared.clear()
            LiveFeed.shared.refreshNow()
            AlertsStore.shared.refresh()
        }
    }

    /// Link again to change what this Mac may do: the old token is removed
    /// first so the wallet keeps at most one entry for this Mac.
    func relink() {
        Task {
            await BlueAgentAPI.unlink()
            me = nil
            beginLink()
        }
    }

    static func open(_ urlString: String?) {
        guard let s = urlString, let u = URL(string: s), u.scheme == "https" || u.host == "localhost" else { return }
        NSWorkspace.shared.open(u)
    }

    static func short(_ a: String) -> String { a.count > 12 ? "\(a.prefix(6))…\(a.suffix(4))" : a }
}
