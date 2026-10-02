# Contributing to BlueBot

BlueBot is Blue Agent in your Mac's notch. Issues, ideas and pull requests are
welcome, from a typo to a new card.

## Getting started

```bash
brew install xcodegen
git clone https://github.com/madebyshun/bluebot.git
cd bluebot/mac
xcodegen
xcodebuild -scheme BlueBot -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/BlueBot.app
```

Run the tests before a pull request (from `mac/`):

```bash
bash scripts/test-safe-links.sh
bash scripts/test-screen-geometry.sh
```

To work against a local Blue Agent server:
`defaults write dev.blueagent.bluebot apiBase http://localhost:3000`

## Where things live

| Area | File |
|---|---|
| Island cards (chat, market, chart, alerts, activity, account) | `mac/Sources/App/IslandBlueViews.swift` |
| Chat stream and tool results | `ChatEngine.swift`, `DiscoveryTable.swift` |
| Market, alerts, activity data | `Stores.swift` |
| Blue Agent API and the wallet link | `BlueAgentAPI.swift`, `BlueAgentLink.swift` |
| Notch window and animation | `IslandWindowController.swift`, `IslandRootView.swift` |
| Sounds (generated, no samples) | `scripts/make-sounds.py` |

## The rules that keep BlueBot trustworthy

These are not style preferences. A pull request that breaks one will not be
merged, however good the rest is.

1. **BlueBot never holds a key and never signs.** It works through a link the
   wallet's owner approves on blueagent.dev. No private keys, seed phrases or
   signing code in this repo.
2. **Every number comes from a source.** Prices, changes, charts and checks
   come from Blue Agent's API. If a value cannot be read, show that (a dash, an
   empty state), never a guess or a placeholder that looks real.
3. **Say which chain.** Base and Robinhood Chain share tickers. A token is a
   chain plus an address, never a symbol alone.
4. **Verdicts are decided by Blue Agent, not by the app.** BlueBot shows the
   pre-trade check's PASS, WARN or BLOCK as it comes back; it does not soften
   or recolour it.
5. **No telemetry, no third-party trackers.** BlueBot talks to Blue Agent's
   API and nothing else.
6. **No Coucou assets.** Its name, Mochi character, icons, sounds and media are
   not MIT. Use BlueBot's own (see `LICENSE`).

## Good first contributions

- A keyboard shortcut that opens the chat card from anywhere
- Charts for stock tokens on Base and Robinhood Chain in the Stocks tab
- Vietnamese (and other) translations of the UI
- A sound picker, or softer/louder sound sets from `make-sounds.py`
- Better empty states and loading states in the cards
- Accessibility: VoiceOver labels on the island controls

Open an issue first for anything bigger than a small fix, so the idea can be
shaped before you spend a weekend on it.

## Pull requests

- One change per pull request, with a short description of what and why.
- Include a screenshot for anything visual.
- Keep the code in the style around it.
- By contributing you agree your work is released under the MIT License in
  `LICENSE`.
