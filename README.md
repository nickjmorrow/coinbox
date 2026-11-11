<img src="App/Mac/Assets.xcassets/AppIcon.appiconset/icon-256@1x.png" width="96" align="right" alt="Coinbox icon">

# Coinbox

A native, local-first envelope budgeting app for Mac and iPhone, in the style of YNAB, built so an AI assistant can work on the same budget through a command line and an MCP server.

## What it does

- **Zero-based budgeting**: give every dollar a job each month. Ready to Assign, per-category assigned / activity / available, credit card payment categories, overspending and rollover, spending targets (weekly, monthly, by date) and one-step auto-assign.
- **Registers and reconciliation**: accounts, transactions with splits, transfers, payees, approve/categorize in bulk, and reconcile against the bank's balance.
- **Bank import**: pulls activity from [SimpleFIN](https://www.simplefin.org) (a read-only bank data bridge) as unapproved transactions, links card payments, and runs ordered import rules (first match wins) to rename payees and set categories. A one-time importer can rebuild the plan from YNAB and diff every number against it.
- **Planning tools**: a month review (what each category spent against next month's plan), runway (months of cash at the current cost of living), a credit card payoff planner (avalanche or snowball), and splitting an Amazon charge by the items in the order.
- **Every change is undoable**: all edits go through one op log with stored inverses; undo is per author, so an assistant's changes can be reverted without touching yours.
- **Multi-device sync**: a small self-hosted hub orders changes from every device and applies them with last-writer-wins per entity. The iPhone app adds a home-screen widget with Ready to Assign, runway and your pinned categories.

## How it works

```
 Mac app ─┐                                   ┌─ coinbox CLI ── MCP server (Python)
iPhone app┼─ CoinboxUI ── CoinboxCore ── SQLite ┤
  widget ─┘   (SwiftUI)    (engine)    (GRDB) └─ sync-serve (hub) ◄── HTTP ── other devices
```

- **`Core`** (`CoinboxCore`) is the whole budget engine: the schema and store (SQLite via GRDB), the budget calculator, every write expressed as an `Op` that is logged, synced and inverted for undo, the rule engine, YNAB and SimpleFIN importers, the AI categorizer and the sync client and hub.
- **`UI`** (`CoinboxUI`) holds the SwiftUI views and the app model shared by the Mac and iPhone apps. The Mac app is a sidebar of Plan, Review, registers, Card Payoff, Rules, Payees and Settings; the iPhone app is built for checking a category before spending, entering a cash spend and approving imports.
- **`CLI`** is the `coinbox` command. It prints JSON, covers everything the apps can do (plus SQL reads, schema and the change log), and also runs the sync hub (`coinbox sync-serve`).
- **`App`** is an XcodeGen project with the Mac app, the iPhone app and its widget extension. The iPhone app writes a small snapshot into an App Group for the widget to read.
- **`mcp`** is a dependency-free Python MCP server (49 tools) that shells out to the CLI, so the assistant and the command line behave identically. Its writes are recorded as author `claude`.

Each device keeps a full copy of the database. `coinbox sync` (and the apps, every couple of minutes and on returning to the foreground) pushes local ops to the hub and pulls everyone else's; per-entity logical clocks decide conflicts, so an edit made after seeing someone else's always wins even if a device's clock runs behind. The hub binds to 127.0.0.1 and authenticates devices by token; it is meant to sit behind a private tunnel such as `tailscale serve`.

## Tech stack

Swift 6 (Swift Package Manager, Swift Testing), SwiftUI, WidgetKit, GRDB/SQLite, swift-argument-parser, XcodeGen; Python 3 standard library for the MCP server.

## Getting started

Requirements: macOS 15+, Xcode 16+ (Swift 6 toolchain), [XcodeGen](https://github.com/yonaskolb/XcodeGen) for the app targets, Python 3 for the MCP server. iPhone builds target iOS 18.

```bash
cp .env.example .env    # optional: DEVELOPMENT_TEAM for iOS device builds, HUB_HOST for the hub deploy script
```

**Command line**

```bash
swift build --package-path CLI -c release
CLI/.build/release/coinbox --help
```

**Mac app with demo data**

```bash
scripts/seed-demo.sh /tmp/coinbox-demo.sqlite      # needs the release CLI above
scripts/build-mac.sh                                # generates App/Coinbox.xcodeproj and builds into App/build.noindex
open -n --env COINBOX_DB=/tmp/coinbox-demo.sqlite App/build.noindex/Build/Products/Debug/Coinbox.app
```

Without `COINBOX_DB` the apps and CLI use `~/Library/Application Support/Coinbox/coinbox.sqlite`.

**iPhone app**: run `scripts/generate-project.sh`, open `App/Coinbox.xcodeproj` and run the `CoinboxiOS` scheme (set `DEVELOPMENT_TEAM` in `.env` for a device).

**MCP server**: link the CLI onto your PATH (or set `COINBOX_BIN`), then add the server to Claude Code:

```bash
ln -s "$PWD/CLI/.build/release/coinbox" ~/.local/bin/coinbox
claude mcp add coinbox -- python3 "$PWD/mcp/coinbox_mcp.py"
```

**Sync hub** (optional): `scripts/deploy-hub.sh --load` copies the source to the ssh host named by `HUB_HOST`, builds the CLI there, creates a token file and installs a launchd agent running `coinbox sync-serve` on port 8791. Point each device at it with `coinbox sync-setup`. If a SimpleFIN access URL has been claimed on the server (`coinbox simplefin-claim`), the hub also imports bank activity every 6 hours.

Other environment variables (`YNAB_TOKEN`, `ANTHROPIC_API_KEY`, `COINBOX_AUTOSYNC`) are described in [.env.example](.env.example).

## Tests

```bash
swift test --package-path Core     # 252 tests: budget math, targets, ops and undo, rules, importers, sync
swift test --package-path UI       # 14 tests: the app model
swift test --package-path CLI      # 33 tests: commands end to end against a temp database
swift build --package-path CLI -c release && python3 -m unittest discover -s mcp   # 10 tests: MCP protocol and tools
```

The MCP tests drive the real release binary, so build it first; they skip otherwise.

## Project layout

```
Core/      CoinboxCore: budget engine, SQLite store, ops/undo, rules, importers, sync
UI/        CoinboxUI: SwiftUI views and app model shared by Mac and iPhone
CLI/       the coinbox command and the sync hub server
App/       XcodeGen project: Mac app, iPhone app, widget extension
mcp/       MCP server wrapping the CLI, and its tests
scripts/   build, demo seed, project generation, hub deploy
design/    app icon source SVGs
```

`CLAUDE.md` holds the working notes used when developing with Claude Code.

## License

See [LICENSE](LICENSE).
