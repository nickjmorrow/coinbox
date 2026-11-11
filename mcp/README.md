# coinbox-mcp

MCP server for Claude (stdio). Wraps the `coinbox` CLI, so every tool behaves exactly like the command line, and everything Claude writes is recorded as author `claude` (undo with `undo_claude`).

Needs `coinbox` on PATH or at `~/.local/bin/coinbox`: `swift build --package-path CLI -c release`, then link `CLI/.build/release/coinbox` to `~/.local/bin/coinbox` (or set `COINBOX_BIN`). The database defaults to `~/Library/Application Support/Coinbox/coinbox.sqlite`, the same file the Mac app opens (override with `COINBOX_DB`).

Add to Claude Code: `claude mcp add coinbox -- python3 <repo>/mcp/coinbox_mcp.py`

Tests (need the release CLI built): `python3 -m unittest discover -s mcp`
