# Coinbox

A native budgeting app for Mac and iPhone in the style of YNAB: single user, local-first, built so Claude can use it through the `coinbox` CLI and an MCP server (`mcp/`).

Parts: `Core` (the budget engine, SQLite store, YNAB and SimpleFIN import, rules, sync), `UI` (SwiftUI views), `CLI` (the `coinbox` command and sync hub), `App` (Mac, iPhone and widget targets), `mcp` (MCP server wrapping the CLI). Build and test commands are in `CLAUDE.md`.
