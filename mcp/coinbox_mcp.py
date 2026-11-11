#!/usr/bin/env python3
"""Coinbox MCP server (stdio). A thin wrapper: every tool runs the `coinbox` CLI, so the CLI and Claude behave identically.

Environment: COINBOX_DB (database file, default ~/Library/Application Support/Coinbox/coinbox.sqlite), COINBOX_BIN (path to coinbox, default
`coinbox` on PATH or ~/.local/bin/coinbox), COINBOX_AUTOSYNC=0 to skip the quiet `coinbox sync` before and after calls. Everything Claude writes is
recorded as author `claude`, so undo_claude can revert it.
"""
import json
import os
import shutil
import subprocess
import sys

PROTOCOL = "2025-06-18"
COINBOX = os.environ.get("COINBOX_BIN") or shutil.which("coinbox") or os.path.expanduser("~/.local/bin/coinbox")

INSTRUCTIONS = (
    "Coinbox is the user's budgeting app (it replaces YNAB): accounts, categories, monthly assignments, transactions, import rules. "
    "Amounts in records are milliunits (1/1000 of a dollar): $12.34 is 12340; outflows are negative. assign and move_money take dollars as text. Dates are YYYY-MM-DD, months YYYY-MM. "
    "Everything you write is logged as Claude and undone with undo_claude. For any bulk change (apply_rules, approve, categorize, delete_transactions) run it with preview=true first, "
    "show what will change, then run it for real. Never categorize an outflow to Ready to Assign (it is refused); reimbursements are inflows to the Reimbursed category. "
    "Approving one side of a transfer approves the other. Rules are ordered and the first match wins, so keep specific rules before general ones. "
    "A credit card account automatically gets a payment category; do not create one yourself. For questions nobody planned for use schema then sql."
)


def S(desc, **props):
    return ({"type": "object",
             "properties": {k: {"type": v[0], "description": v[1], **({"items": {"type": "string"}} if v[0] == "array" else {})} for k, v in props.items()},
             "required": [k for k, v in props.items() if len(v) < 3], "additionalProperties": False}, desc)


def opt(args, flag, value):
    # "--flag=value" so a value that starts with "-" is not mistaken for another option
    return args + [f"{flag}={value}"] if value not in (None, "") else args


def flag(args, name, on):
    return args + [name] if on else args


def put_json(base, a, key):
    value = a[key]
    return base + ["--json", value if isinstance(value, str) else json.dumps(value)]


def positional(base, *values):
    return base + ["--"] + [str(v) for v in values]


ACCOUNT_SHAPE = ("{name, id?, kind?: checking|savings|cash|creditCard|mortgage|loan|asset, onBudget?: true (false for tracking accounts), closed?, note?}. "
                 "A new creditCard also gets its payment category.")
CATEGORY_SHAPE = "{name, groupID, id?, order?, hidden?, note?, kind?: {type: 'normal'} (default)}"
GROUP_SHAPE = "{name, id?, order?, hidden?}"
PAYEE_SHAPE = "{name, id?, defaultCategoryID?, defaultLocked?, transferAccountID?}"
TX_SHAPE = ("{accountID, date, amount (milliunits, negative = outflow), id?, payeeID?, categoryID? (null for transfers and splits), memo?, cleared?: uncleared|cleared|reconciled, approved?, "
            "splits?: [{categoryID, amount, memo?}] (two or more, summing to amount, parent categoryID null), rawPayee?}. With an existing id it replaces that transaction.")
TARGET_SHAPE = ("{categoryID, amount (milliunits), cadence: {type:'weekly', isoWeekday:1-7} | {type:'monthly', day} | {type:'yearly', month, day} | "
                "{type:'byDate', date:'YYYY-MM-DD'} | {type:'everyMonths', n, firstDue:'YYYY-MM-DD'}}")
RULE_SHAPE = ("{name, id?, payee?: {mode:'contains'|'equals'|'regex', text} (matches the bank's raw payee text), amount?: {type:'equals', amount} | {type:'range', min, max} | {type:'endsWithCents', cents}, "
              "accountIDs?: [..], memo?: {mode, text}, actions: {renamePayee?, categoryID?, memo?, approve?}}. All present conditions must match.")


def crud(noun, plural, cmd, shape, with_put=True):
    out = {
        f"list_{plural}": (*S(f"All {plural.replace('_', ' ')}."), lambda a, c=cmd: [c, "list"]),
        f"get_{noun}": (*S(f"One {noun.replace('_', ' ')} by id.", id=("string", "Id")), lambda a, c=cmd: [c, "get", a["id"]]),
        f"delete_{noun}": (*S(f"Delete a {noun.replace('_', ' ')} by id (refused if it has history).", id=("string", "Id")), lambda a, c=cmd: [c, "delete", a["id"]]),
    }
    if with_put:
        out[f"put_{noun}"] = (*S(f"Create or replace a {noun.replace('_', ' ')}: {shape}", **{noun: ("object", shape)}), lambda a, c=cmd, n=noun: put_json([c, "put"], a, n))
    return out


TOOLS = {}
TOOLS.update(crud("account", "accounts", "account", ACCOUNT_SHAPE))
TOOLS.update(crud("category_group", "category_groups", "category-group", GROUP_SHAPE))
TOOLS.update(crud("category", "categories", "category", CATEGORY_SHAPE))
TOOLS.update(crud("payee", "payees", "payee", PAYEE_SHAPE))
TOOLS.update(crud("transaction", "transactions", "transaction", TX_SHAPE))
del TOOLS["list_transactions"]
TOOLS.update({
    "list_transactions": (*S("Transactions, oldest first, optionally for one account and a date range.", account=("string", "Account id", "opt"),
                             since=("string", "On or after YYYY-MM-DD", "opt"), until=("string", "On or before YYYY-MM-DD", "opt")),
                          lambda a: opt(opt(opt(["transaction", "list"], "--account", a.get("account")), "--since", a.get("since")), "--until", a.get("until"))),
    "approve": (*S("Approve transactions. A transfer's other side is approved too. Preview first for more than a couple.", ids=("array", "Transaction ids"), preview=("boolean", "Show the changes without making them", "opt")),
                lambda a: positional(flag(["transaction", "approve"], "--preview", a.get("preview")), *a["ids"])),
    "categorize": (*S("Set one category on many transactions (splits and on-budget transfers are skipped and reported). Preview first.", ids=("array", "Transaction ids"),
                      category=("string", "Category id"), approve=("boolean", "Also approve them", "opt"), preview=("boolean", "Show the changes without making them", "opt")),
                   lambda a: positional(flag(flag(opt(["transaction", "categorize"], "--category", a["category"]), "--approve", a.get("approve")), "--preview", a.get("preview")), *a["ids"])),
    "delete_transactions": (*S("Delete many transactions (a transfer's other side goes too). Preview first.", ids=("array", "Transaction ids"), preview=("boolean", "Show the changes without making them", "opt")),
                            lambda a: positional(flag(["transaction", "delete-many"], "--preview", a.get("preview")), *a["ids"])),
    "list_targets": (*S("Spending targets."), lambda a: ["target", "list"]),
    "put_target": (*S(f"Set a category's target: {TARGET_SHAPE}", target=("object", TARGET_SHAPE)), lambda a: put_json(["target", "put"], a, "target")),
    "delete_target": (*S("Remove a category's target.", category_id=("string", "Category id")), lambda a: positional(["target", "delete"], a["category_id"])),
    "assign": (*S("Set what a category is assigned in a month (replaces the old amount).", category_id=("string", "Category id"), month=("string", "YYYY-MM"), dollars=("string", "Dollars, e.g. '250.00'")),
               lambda a: positional(["assign"], a["category_id"], a["month"], a["dollars"])),
    "move_money": (*S("Move money between two categories in a month, as one change.", from_category=("string", "Category id to take from"), to_category=("string", "Category id to give to"),
                      month=("string", "YYYY-MM"), dollars=("string", "Dollars, positive")),
                   lambda a: positional(["move"], a["from_category"], a["to_category"], a["month"], a["dollars"])),
    "plan": (*S("The plan for a month: Ready to Assign, and every category's assigned, activity, available, underfunded and overspending.", month=("string", "YYYY-MM")),
             lambda a: positional(["plan"], a["month"])),
    "auto_assign": (*S("Assign every underfunded category what it needs, in plan order, until Ready to Assign runs out. Preview first.", month=("string", "YYYY-MM"), preview=("boolean", "Show the assignments without making them", "opt")),
                    lambda a: positional(flag(["auto-assign"], "--preview", a.get("preview")), a["month"])),
    "runway": (*S("Cash in on-budget cash accounts divided by Cost to Be Me (the monthly need of every target), in months.", month=("string", "YYYY-MM to price targets in (default this month)", "opt")),
               lambda a: opt(["runway"], "--month", a.get("month"))),
    "money_moves": (*S("Who changed what was assigned in a month, newest first.", month=("string", "YYYY-MM")), lambda a: positional(["money-moves"], a["month"])),
    "reconcile": (*S("Lock an account's cleared transactions as reconciled against the bank's balance. A difference needs adjust=true (adds a Reconciliation Balance Adjustment).",
                     account_id=("string", "Account id"), date=("string", "Statement date YYYY-MM-DD"), balance=("string", "The bank's balance in dollars"), adjust=("boolean", "Adjust for any difference", "opt")),
                  lambda a: positional(flag(opt(opt(["reconcile"], "--date", a["date"]), "--balance", a["balance"]), "--adjust", a.get("adjust")), a["account_id"])),
    "search_transactions": (*S("Find transactions, newest first; every given filter must match. text looks at payee, raw payee, memo, category, amount and date.", text=("string", "Text", "opt"),
                               account=("string", "Account id", "opt"), category=("string", "Category id", "opt"), approved=("boolean", "Only approved (true) or unapproved (false)", "opt"),
                               uncategorized=("boolean", "Only transactions with no category", "opt"), from_date=("string", "On or after YYYY-MM-DD", "opt"), to_date=("string", "On or before YYYY-MM-DD", "opt")),
                            lambda a: flag(opt(opt(opt(opt(opt(opt(["transaction", "search"], "--text", a.get("text")), "--account", a.get("account")), "--category", a.get("category")),
                                                       "--approved", None if a.get("approved") is None else str(a["approved"]).lower()), "--from", a.get("from_date")), "--to", a.get("to_date")),
                                           "--uncategorized", a.get("uncategorized"))),
    "list_card_terms": (*S("Each credit card's APR (basis points, 2499 = 24.99%) and minimum payment (milliunits)."), lambda a: ["card-terms", "list"]),
    "put_card_terms": (*S("Set a card's APR and minimum payment for the payoff planner. The user tells you the APR; never guess it.", account=("string", "Credit card account id"),
                          apr=("string", "APR in percent, like 24.99"), minimum=("string", "Minimum monthly payment in dollars")),
                       lambda a: opt(opt(opt(["card-terms", "put"], "--account", a["account"]), "--apr", a["apr"]), "--minimum", a["minimum"])),
    "payoff_plan": (*S("A card payoff plan from the balances and the card terms: avalanche (highest APR first) or snowball (smallest balance first), payoff months and interest saved against minimums only.",
                       budget=("string", "Dollars a month for all cards together"), strategy=("string", "avalanche or snowball", "opt"), month=("string", "First month YYYY-MM", "opt")),
                    lambda a: opt(opt(opt(["payoff"], "--budget", a["budget"]), "--strategy", a.get("strategy")), "--month", a.get("month"))),
    "amazon_split": (*S("Split an Amazon charge by what was in the order (read the order history in Chrome; Amazon has no API). Tax is prorated across the items and the lines add up exactly. Give tax in dollars, or leave it out to work it out from the charge.",
                        transaction_id=("string", "The Amazon transaction id"), order=("string", "Amazon order number"),
                        items=("array", "Items: {name, amount (milliunits before tax, positive), categoryID}"), tax=("string", "Total tax in dollars", "opt")),
                     lambda a: positional(opt(opt(["amazon-split"], "--order", a["order"]), "--tax", a.get("tax")) + ["--items", json.dumps(a["items"])], a["transaction_id"])),
    "get_amazon_order": (*S("The recorded Amazon order for a transaction.", transaction_id=("string", "Transaction id")), lambda a: positional(["amazon-link"], a["transaction_id"])),
    "list_rules": (*S("Import rules in order (first match wins)."), lambda a: ["rule", "list"]),
    "put_rule": (*S(f"Create or replace one rule: {RULE_SHAPE}", rule=("object", RULE_SHAPE)), lambda a: put_json(["rule", "put"], a, "rule")),
    "put_rules": (*S("Load a whole ordered ruleset; a rule's order is its position in the array. replace=true removes every other rule.", rules=("array", "Rules, shaped like put_rule's"),
                     replace=("boolean", "Remove rules not in the list", "opt")),
                  lambda a: flag(put_json(["rule", "put-many"], a, "rules"), "--replace", a.get("replace"))),
    "delete_rule": (*S("Delete a rule.", id=("string", "Rule id")), lambda a: ["rule", "delete", a["id"]]),
    "apply_rules": (*S("Run the rules over unapproved transactions (or the given ids): rename payee, set category, set memo, approve. With no matching rule a transaction gets its payee's default category. Preview first.",
                       ids=("array", "Only these transaction ids", "opt"), preview=("boolean", "Show the changes without making them", "opt")),
                    lambda a: flag(opt(["rule", "apply"], "--ids", ",".join(a["ids"]) if a.get("ids") else None), "--preview", a.get("preview"))),
    "import_ynab": (*S("Rebuild the plan from YNAB (read only; needs YNAB_TOKEN). Without apply it only reports.", plan=("string", "YNAB plan id"), apply=("boolean", "Write the import", "opt"),
                       plug_opening_rta=("boolean", "Add one inflow so Ready to Assign matches YNAB's first month", "opt"), since=("string", "YYYY-MM-DD (default 2026-01-01)", "opt")),
                    lambda a: opt(flag(flag(opt(["import-ynab"], "--plan", a["plan"]), "--apply", a.get("apply")), "--plug-opening-rta", a.get("plug_opening_rta")), "--since", a.get("since"))),
    "compare_ynab": (*S("Every number that differs from YNAB's (needs YNAB_TOKEN).", plan=("string", "YNAB plan id"), since=("string", "YYYY-MM-DD (default 2026-01-01)", "opt")),
                     lambda a: opt(opt(["ynab-compare"], "--plan", a["plan"]), "--since", a.get("since"))),
    "schema": (*S("The database tables and columns, for writing sql queries. Amounts are milliunits."), lambda a: ["schema"]),
    "sql": (*S("Read-only SQL (one SELECT) for questions nobody planned for. Call schema first.", query=("string", "A SELECT statement"), limit=("integer", "Max rows (default 500)", "opt")),
            lambda a: opt(["sql"], "--limit", a.get("limit")) + ["--", a["query"]]),
    "changes": (*S("The change log: what was changed, by whom, and whether it was undone or skipped.", by=("string", "mac, iphone, claude, bank or import", "opt"), since=("integer", "Milliseconds since epoch", "opt")),
                lambda a: opt(opt(["changes"], "--by", a.get("by")), "--since", a.get("since"))),
})

READ_ONLY = {n for n in TOOLS if n.startswith(("list_", "get_"))} | {"plan", "schema", "sql", "changes", "compare_ynab", "runway", "money_moves", "search_transactions", "payoff_plan", "get_amazon_order"}
AUTOSYNC = os.environ.get("COINBOX_AUTOSYNC", "1") != "0"
PREVIEWABLE = {"approve", "categorize", "delete_transactions", "apply_rules", "import_ynab", "auto_assign"}


def sync_quietly():
    """Keep this copy in step with the sync hub when sync is set up (a no-op, quickly, when it isn't, or when the hub is unreachable)."""
    if not AUTOSYNC:
        return
    try:
        subprocess.run([COINBOX, "sync"], capture_output=True, text=True, timeout=8)
    except (OSError, subprocess.TimeoutExpired):
        pass


def run_coinbox(args):
    argv = [COINBOX] + args
    if "--author" not in argv:
        i = argv.index("--") if "--" in argv else len(argv)
        argv[i:i] = ["--author", "claude"]
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"could not run coinbox: {e}", True
    out = (p.stdout or "").strip()
    if p.returncode != 0:
        return (p.stderr.strip() or out or f"coinbox exited {p.returncode}"), True
    return out or "ok", False


def run_tool(name, args):
    sync_quietly()                      # pick up what the phone and Mac did since the last call
    text, err = _run_tool(name, args)
    wrote = name not in READ_ONLY and not args.get("preview") and not (name == "import_ynab" and not args.get("apply"))
    if wrote and not err:
        sync_quietly()                  # and send what this call changed
    return text, err


def _run_tool(name, args):
    if name == "undo_claude":
        results = []
        for _ in range(max(1, int(args.get("last") or 1))):
            text, err = run_coinbox(["undo"])
            if err:
                return text, True
            results.append(json.loads(text))
            if results[-1].get("undone", 0) == 0 and not results[-1].get("skipped"):
                break
        return json.dumps(results if len(results) > 1 else results[0], indent=1), False
    if name not in TOOLS:
        return f"unknown tool: {name}", True
    try:
        return run_coinbox(TOOLS[name][2](args))
    except KeyError as e:
        return f"missing argument: {e}", True


TOOL_LIST = [{"name": n, "description": d, "inputSchema": s} for n, (s, d, _) in TOOLS.items()]
for t in TOOL_LIST:
    props = t["inputSchema"]["properties"]
    for key in ("transaction", "account", "category", "category_group", "payee", "target", "rule"):
        if key in props and props[key]["type"] == "object":
            props[key]["additionalProperties"] = True
    if "items" in props:
        props["items"]["items"] = {"type": "object"}
    if "rules" in props:
        props["rules"]["items"] = {"type": "object"}
TOOL_LIST.append({"name": "undo_claude", "description": "Undo Claude's latest change(s) (a bulk edit is one change). A change is skipped, not forced, if the user edited the same thing afterwards.",
                  "inputSchema": S("", last=("integer", "How many changes (default 1)", "opt"))[0]})


def handle(msg):
    method, mid = msg.get("method"), msg.get("id")
    if mid is None:  # notification
        return None

    def ok(result): return {"jsonrpc": "2.0", "id": mid, "result": result}

    def err(code, text): return {"jsonrpc": "2.0", "id": mid, "error": {"code": code, "message": text}}

    if method == "initialize":
        return ok({"protocolVersion": PROTOCOL, "capabilities": {"tools": {}}, "serverInfo": {"name": "coinbox", "version": "1.0"}, "instructions": INSTRUCTIONS})
    if method == "ping":
        return ok({})
    if method == "tools/list":
        return ok({"tools": TOOL_LIST})
    if method == "tools/call":
        params = msg.get("params") or {}
        text, is_err = run_tool(params.get("name", ""), params.get("arguments") or {})
        return ok({"content": [{"type": "text", "text": text}], "isError": is_err})
    return err(-32601, f"method not found: {method}")


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        try:
            reply = handle(msg)
        except Exception as e:  # never die on one bad request
            reply = {"jsonrpc": "2.0", "id": msg.get("id"), "error": {"code": -32603, "message": str(e)}}
        if reply is not None:
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
