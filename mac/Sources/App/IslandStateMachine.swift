import Foundation

/// Pure 4-state FSM for island open/close logic.
/// No AppKit / AppState dependencies — communicates via `onTransition`.
@MainActor
final class IslandStateMachine {

    enum State: Equatable {
        case hidden   // island invisible (notch size)
        case petit    // compact island (notch + ears)
        case home     // expanded, overview
        case greeting // expanded, greeting animation
    }

    private(set) var state: State = .hidden

    /// Fired on every transition: (from, to)
    var onTransition: ((State, State) -> Void)?

    /// home → petit delay (seconds). Override for debug.
    var homeToPetitDelay: TimeInterval = 15
    /// petit → hidden delay (seconds). Override for debug.
    var petitToHiddenDelay: TimeInterval = 60
    /// greeting → petit delay after greeting animation ends (no hover). ~0.6s syncs with canvas collapse.
    var greetAutoCollapseDelay: TimeInterval = 0.6
    /// greeting → petit delay when mouse is hovering over the greeting.
    var greetHoverCollapseDelay: TimeInterval = 10
    /// The greeting animation has reached its end pose (greetComplete).
    private var greetDone = false

    private var petitHideWork: DispatchWorkItem?
    private var homeCollapseWork: DispatchWorkItem?
    private var greetCollapseWork: DispatchWorkItem?

    // MARK: – Inputs

    /// App launched or debug "launch greeting"
    func launch() {
        cancelTimers()
        transition(to: .greeting)
    }

    /// Mouse entered the island notch area
    func mouseEntered() {
        switch state {
        case .hidden, .petit:
            // Every hover plays the greeting; the mouse is already in, so hold it open.
            cancelTimers()
            transition(to: .greeting)
            scheduleGreetCollapse(delay: greetHoverCollapseDelay)
        case .home:
            homeCollapseWork?.cancel()
            homeCollapseWork = nil
        case .greeting:
            // Mouse hovering during greeting — cancel short auto-collapse, extend to hover delay
            scheduleGreetCollapse(delay: greetHoverCollapseDelay)
        }
    }

    /// Mouse left the island notch area
    func mouseLeft() {
        switch state {
        case .hidden:
            break
        case .petit:
            schedulePetitHide()
        case .home:
            scheduleHomeCollapse()
        case .greeting:
            greetCollapseWork?.cancel(); greetCollapseWork = nil
            // A quick sweep past the notch still plays the whole greeting:
            // greetComplete then folds it. Once it has played, leaving folds it now.
            if greetDone { transition(to: .petit) }
        }
    }

    /// Compact island (or the greeting) clicked.
    /// Also accepts `.hidden`: after an alert the island can be on screen while the
    /// FSM never saw the mouse enter (it was already there), and the click must still open it.
    func click() {
        guard state == .petit || state == .hidden || state == .greeting else { return }
        cancelTimers()
        transition(to: .home)
    }

    /// The app hid the island on its own (e.g. `AppState.syncMode()` when the last
    /// task ends). Mirror it without side effects, so the next hover peeks again
    /// instead of being swallowed by a FSM that still thinks the island is `.petit`.
    func hiddenExternally() {
        guard state == .petit else { return }
        cancelTimers()
        state = .hidden
    }

    /// The app folded the island itself (Escape, Settings, OK button, auto-close).
    /// Move to `.petit` right away so hover and click keep working; waiting for the
    /// 15 s home timer left the island compact on screen while the FSM still said `.home`.
    func collapse() {
        guard state == .home || state == .greeting else { return }
        cancelTimers()
        transition(to: .petit)
    }

    /// Greeting animation finished (called at T.end ≈ 4.60 s).
    /// Schedules auto-collapse. Does not override a longer hover timer already running.
    func greetComplete() {
        guard state == .greeting else { return }
        greetDone = true
        // If mouse entered before this fires (hover timer already running), don't override it
        if greetCollapseWork == nil {
            scheduleGreetCollapse(delay: greetAutoCollapseDelay)
        }
    }

    private func scheduleGreetCollapse(delay: TimeInterval) {
        greetCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .greeting else { return }
            self.transition(to: .petit)
        }
        greetCollapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Non-alert work event: show compact from hidden (HookServer reveal)
    func reveal() {
        guard state == .hidden else { return }
        cancelTimers()
        transition(to: .petit)
        schedulePetitHide()
    }

    // MARK: – Timers

    private func schedulePetitHide() {
        petitHideWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .petit else { return }
            self.transition(to: .hidden)
        }
        petitHideWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + petitToHiddenDelay, execute: item)
    }

    private func scheduleHomeCollapse() {
        homeCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .home else { return }
            self.transition(to: .petit)
        }
        homeCollapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + homeToPetitDelay, execute: item)
    }

    func cancelTimers() {
        petitHideWork?.cancel();    petitHideWork = nil
        homeCollapseWork?.cancel(); homeCollapseWork = nil
        greetCollapseWork?.cancel(); greetCollapseWork = nil
    }

    private func transition(to new: State) {
        guard new != state else { return }
        let old = state
        state = new
        if new == .greeting { greetDone = false }
        onTransition?(old, new)
    }

}
