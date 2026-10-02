# BlueBot

**Blue Agent for traders, in your Mac's notch.**

Ask Blue Agent what's moving, chart and check a token before you buy it, and
get told the moment your price alerts fire, without opening a browser.
Built on [Blue Agent](https://blueagent.dev).

- **Chat.** Ask in plain words: *"what's trending on Base?"*, *"what launched in
  the last hour on Robinhood Chain?"*. Blue Agent answers from live sources and
  can draft a price alert you arm right here.
- **Market.** Tokens on Base and stock tokens on Base (Coinbase B20) and
  Robinhood Chain, with Chainlink oracle vs DEX price. Pin any token, drag
  your list into your own order, and tap a token for its 24H / 7D / 30D chart.
- **Check.** Paste a token address and get Blue Agent's pre-trade check:
  PASS, WARN or BLOCK, with the reason. The verdict is decided in code, not by a
  model.
- **Alerts.** Price above/below or % moves, checked every 5 minutes, free, up
  to 20. They fire in your notch.
- **Activity.** Every alert, trade and check on your wallet, in one timeline.

Trading is not in BlueBot yet. When Blue Agent prepares a trade in chat,
BlueBot names it and you sign it in Blue Chat with your wallet.

## Your wallet, linked

BlueBot uses the wallet you already have on Blue Agent. It never creates one
and never holds a key, so it cannot sign or move funds.

In the notch, 👤 → **Link wallet**, BlueBot shows a code and opens
app.blueagent.dev/link. Approve the code with your wallet and choose what this
Mac may do:

- see your alerts and activity (always);
- chat with Blue Agent on your wallet's credits (when they run out,
  **Top up credits** opens the top-up page, where your wallet pays);
- set and change price alerts.

Change it any time with 👤 → **Change**, or unlink the Mac there or on
the web.

## Install

Requires macOS 14 or later.

1. Download `BlueBot.zip` from [Releases](../../releases) and unzip it.
2. Move **BlueBot.app** to Applications and open it.
3. This build is not notarized by Apple yet. The first time, macOS says it
   can't verify the developer: open **System Settings → Privacy & Security**,
   scroll down and click **Open Anyway** (once).
4. Click the BlueBot icon in the menu bar → **Open BlueBot** (⌘B) → the 👤 tab
   → **Link wallet**.

## Build from source

Requirements: macOS 14+, Xcode 16+ (tested on Xcode 27.0), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/madebyshun/bluebot.git
cd bluebot/mac
xcodegen
xcodebuild -scheme BlueBot -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/BlueBot.app
```

Tests (from `mac/`): `bash scripts/test-safe-links.sh`,
`bash scripts/test-screen-geometry.sh`.

Developer setting (Account → Advanced): the Blue Agent server
(`defaults write dev.blueagent.bluebot apiBase http://localhost:3000`).

## How it works

BlueBot talks only to Blue Agent's API (`app.blueagent.dev`). No telemetry.

| Feature | Blue Agent endpoint |
|---|---|
| Link | `/api/devices/code`, `/api/devices/token`, `/api/devices/me` |
| Chat | `/api/devices/chat` (link token, `chat`) |
| Market | `/api/base-tokens`, `/api/hood/snapshot` |
| Check | `/api/pretrade-check` |
| Alerts | `/api/watches` (link token; changes need `alerts`) |
| Activity | `/api/devices/feed` |
| Credits | `/api/credits/balance/<wallet>` |

## Contributing

BlueBot is open source and built in public. Ideas, issues and pull requests
are welcome: start with [CONTRIBUTING.md](CONTRIBUTING.md), which lists good
first contributions and the few rules that keep BlueBot trustworthy.

## License

MIT, see [LICENSE](LICENSE). The notch island is derived from Coucou (MIT),
whose notice is kept in [LICENSE-COUCOU](LICENSE-COUCOU).

## Origin

The notch app is forked from [Coucou](https://github.com/louis-cfm/coucou) by
Louis Raillé (MIT, see [LICENSE-COUCOU](LICENSE-COUCOU) and `mac/UPSTREAM`).
Coucou's name, Mochi character, icon, sounds and media are not part of this
repository: BlueBot wears Blue Agent's mark.
