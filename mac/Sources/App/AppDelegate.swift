import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ignore SIGPIPE — prevents crash when nb-hook closes socket before we write response
        signal(SIGPIPE, SIG_IGN)
        // Warm up Keychain cache on main thread BEFORE any poller or view touches it
        _ = KeychainStore.shared
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
        setupIsland()
    }

    // MARK: - Menu bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "BlueBot")
        button.image?.size = NSSize(width: 24, height: 18)
        button.image?.accessibilityDescription = "BlueBot"
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Open BlueBot", action: #selector(openIsland), keyEquivalent: "b")
        menu.addItem(withTitle: "Ask Blue Agent", action: #selector(openChat), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func openChat() { islandController?.expand(to: .prompt) }

    @objc private func openIsland() {
        islandController?.expand(to: .overview)
    }

    @objc private func openSettings() { islandController?.expand(to: .settings) }

    // MARK: - Island setup

    private func setupIsland() {
        islandController = IslandWindowController()
        islandController?.showWindow(nil)
        islandController?.fsm.launch()
        // BlueBot runs on Blue Agent: the coding-agent hook server and the
        // service pollers are not started.
        BlueAgentLink.shared.refresh()
        LiveFeed.shared.start()
        MarketStore.shared.refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .openFullSettings, object: nil)
    }
}
