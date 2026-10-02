import SwiftUI
import AppKit

@main
struct BlueBotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // BlueBot's settings live in its panel (Account tab). This scene only
        // satisfies SwiftUI's need for one; it is never shown.
        Settings { EmptyView() }
    }
}
