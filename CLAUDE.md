# Coinbox

This repo is public: tests, fixtures, sample data, docs and comments must be generic, with no personal data (real names, personal media or reading lists, calendars, health, money, machine names).

- Tests: `swift test` in each of `Core`, `UI`, `CLI`; `python3 -m unittest discover -s mcp` (needs `swift build --package-path CLI -c release` first).
- Mac app: `scripts/build-mac.sh [Debug|Release]` builds into `App/build.noindex`. A look at it with invented data: `scripts/seed-demo.sh /tmp/coinbox-demo.sqlite`, then `open -n --env COINBOX_DB=/tmp/coinbox-demo.sqlite <the .app>`.
- Installing the iPhone app on a device:

  ```bash
  cd App && xcodebuild -project Coinbox.xcodeproj -scheme CoinboxiOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath ../build-device.noindex -allowProvisioningUpdates build
  xcrun devicectl device install app --device <iphone-id> ../build-device.noindex/Build/Products/Release-iphoneos/Coinbox.app
  ```
  (`scripts/generate-project.sh` first if `project.yml` changed; the team id comes from `.env`, see `.env.example`.)
- The CLI is `coinbox` (link `CLI/.build/release/coinbox` to `~/.local/bin/coinbox`); the MCP server is `mcp/coinbox_mcp.py`, which can be mounted in another MCP server or added to Claude Code directly (see `mcp/README.md`).
- The hub: `scripts/deploy-hub.sh [--load]` builds on the server named by `HUB_HOST` in `.env` and writes the launchd plist (port 8791, `~/coinbox-hub/`, tokens in `~/.config/coinbox/sync-tokens.json`). `--load` starts it. It can be reached over a tailnet with a `tailscale serve --tcp` listener forwarding to 127.0.0.1:8791. With `~/.config/coinbox/simplefin_access_url` present it also imports bank activity every 6 hours.
- Never put the SimpleFIN access URL, the YNAB token or a sync token in this repo.
- Machine-specific and personal details (device ids, hosts, deploy habits) live in the gitignored `CLAUDE.local.md`.
