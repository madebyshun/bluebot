import AppKit
import SwiftUI

// MARK: - Watch-only link (device code)
//
// For a trader whose wallet is NOT an email wallet (MetaMask, Coinbase
// Wallet…): BlueBot can still show their alerts and activity with a
// read-only token, approved once on app.blueagent.dev/link. It cannot chat
// or trade in this mode — those need the wallet itself (sign in with email).
// The feed itself is read by LiveFeed.

@MainActor
final class BlueAgentLink: ObservableObject {
    static let shared = BlueAgentLink()

    enum Status: Equatable {
        case unlinked
        case requesting
        case waiting(code: String, url: String, expires: Date)
        case linked(wallet: String?, device: String?)
        case failed(String)
    }

    @Published private(set) var status: Status = .unlinked
    private var linkTask: Task<Void, Never>?
    private static let deviceKey = "blueagentDevice"

    private init() {
        if BlueAgentAPI.token != nil { status = .linked(wallet: nil, device: UserDefaults.standard.string(forKey: Self.deviceKey)) }
    }

    var isLinked: Bool { if case .linked = status { return true } else { return false } }

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
                while !Task.isCancelled, Date() < expires {
                    try await Task.sleep(nanoseconds: UInt64(max(code.interval, 3)) * 1_000_000_000)
                    if let tok = try await BlueAgentAPI.pollToken(deviceCode: code.device_code) {
                        KeychainStore.shared.set(BlueAgentAPI.tokenKey, value: tok.access_token)
                        UserDefaults.standard.set(tok.device.name, forKey: Self.deviceKey)
                        self.status = .linked(wallet: nil, device: tok.device.name)
                        LiveFeed.shared.start()
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
        status = BlueAgentAPI.token != nil ? .linked(wallet: nil, device: UserDefaults.standard.string(forKey: Self.deviceKey)) : .unlinked
    }

    func unlink() {
        Task {
            await BlueAgentAPI.unlink()
            UserDefaults.standard.removeObject(forKey: Self.deviceKey)
            status = .unlinked
            LiveFeed.shared.refreshNow()
        }
    }

    static func open(_ urlString: String?) {
        guard let s = urlString, let u = URL(string: s), u.scheme == "https" || u.host == "localhost" else { return }
        NSWorkspace.shared.open(u)
    }
}
