# BlueBot

**Blue Agent for traders, in your Mac's notch.**

Ask Blue Agent what's moving, check a token before you buy it, trade on Base,
and get told the moment your price alerts fire, without opening a browser.
Built on [Blue Agent](https://blueagent.dev).

- **Chat.** Ask in plain words: *"what's trending on Base?"*, *"what launched in
  the last hour on Robinhood Chain?"*. Blue Agent answers from live sources and
  can draft a price alert or a trade for you.
- **Market.** Majors on Base and stock tokens on Base (Coinbase B20) and
  Robinhood Chain, with Chainlink oracle vs DEX price. Every number shows its
  chain and its source.
- **Check.** Paste a token address and get Blue Agent's pre-trade check:
  PASS, WARN or BLOCK, with the reason. The verdict is decided in code, not by a
  model.
- **Trade on Base.** Pre-trade check, 0x quote, exact-amount approval, and the
  swap, signed by your wallet. A BLOCK cannot be signed.
- **Alerts.** Price above/below or % moves, checked every 5 minutes, free, up
  to 20. An automation ("…then buy $25") prepares the trade when it fires and
  waits for you. Nothing trades on its own.
- **Activity.** Every alert, trade and check, in one timeline.

## Your keys

BlueBot never sees a private key. You sign in with your email (the same login
as Blue Chat) and get your own wallet. Its key is held by
[Privy](https://privy.io)'s secure enclave and only signs when you act. Chat
uses your wallet's Blue Agent credits: 500 free every day.

Not an email wallet? Use **Account → Link watch-only** to see your alerts and
activity with a read-only link (no chat or trading).

## Install

Requires macOS 14 or later.

1. Download `BlueBot.zip` from [Releases](../../releases) and unzip it.
2. Move **BlueBot.app** to Applications and open it.
3. This build is not notarized by Apple yet. The first time, macOS says it
   can't verify the developer: open **System Settings → Privacy & Security**,
   scroll down and click **Open Anyway** (once).
4. Click the BlueBot icon in the menu bar → **Open BlueBot** (⌘B) → **Account**
   → sign in with your email.

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

Tests (from `mac/`): `bash scripts/test-evm.sh`, `bash scripts/test-safe-links.sh`,
`bash scripts/test-screen-geometry.sh`.

Developer settings (Account → Advanced): the Blue Agent server
(`defaults write dev.blueagent.bluebot apiBase http://localhost:3000`) and the
Privy app client id.

## How it works

BlueBot talks only to Blue Agent's public API (`app.blueagent.dev`), to Base's
public RPC for balances and receipts, and to Privy for sign-in and signing.
No telemetry.

| Feature | Blue Agent endpoint |
|---|---|
| Sign-in | `/api/auth/nonce`, `/api/auth/session` (SIWE, signed by your wallet) |
| Chat | `/api/chat` |
| Market | `/api/base-tokens`, `/api/hood/snapshot` |
| Check | `/api/pretrade-check` |
| Trade | `/api/swap/quote` (0x), `/api/actions` |
| Alerts | `/api/watches` |
| Activity | `/api/timeline`, `/api/devices/feed` (watch-only) |

## Origin

The notch app is forked from [Coucou](https://github.com/louis-cfm/coucou) by
Louis Raillé (MIT, see [LICENSE-COUCOU](LICENSE-COUCOU) and `mac/UPSTREAM`).
Coucou's name, Mochi character, icon, sounds and media are not part of this
repository: BlueBot wears Blue Agent's mark.
