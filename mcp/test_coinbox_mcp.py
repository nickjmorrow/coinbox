import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
COINBOX_BIN = os.environ.get("COINBOX_BIN") or os.path.join(HERE, "..", "CLI", ".build", "release", "coinbox")


@unittest.skipUnless(os.path.exists(COINBOX_BIN), "build the CLI first: swift build --package-path CLI -c release")
class McpTests(unittest.TestCase):
    def setUp(self):
        self.db = os.path.join(tempfile.mkdtemp(), "coinbox.sqlite")
        env = dict(os.environ, COINBOX_DB=self.db, COINBOX_BIN=COINBOX_BIN, COINBOX_AUTOSYNC="0")
        self.p = subprocess.Popen([sys.executable, os.path.join(HERE, "coinbox_mcp.py")], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env)
        self.n = 0

    def tearDown(self):
        self.p.stdin.close()
        self.p.wait()
        self.p.stdout.close()

    def call(self, method, params=None):
        self.n += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params or {}}) + "\n")
        self.p.stdin.flush()
        return json.loads(self.p.stdout.readline())

    def tool(self, name, **args):
        r = self.call("tools/call", {"name": name, "arguments": args})["result"]
        return r["content"][0]["text"], r["isError"]

    def ok(self, name, **args):
        text, err = self.tool(name, **args)
        self.assertFalse(err, text)
        return json.loads(text)

    def seed(self):
        self.ok("put_account", account={"id": "chk", "name": "Checking"})
        self.ok("put_category_group", category_group={"id": "g", "name": "Spending"})
        for cid in ("groc", "fun"):
            self.ok("put_category", category={"id": cid, "groupID": "g", "name": cid})
        for i, raw in enumerate(["TRADER JOES 1", "TRADER JOES 2", "MOVIE NIGHT"]):
            self.ok("put_transaction", transaction={"id": f"t{i}", "accountID": "chk", "date": "2026-01-0%d" % (i + 1), "amount": -10000, "approved": False, "rawPayee": raw})

    def test_initialize_and_tool_list(self):
        r = self.call("initialize")["result"]
        self.assertEqual(r["serverInfo"]["name"], "coinbox")
        self.assertIn("milliunits", r["instructions"])
        names = {t["name"] for t in self.call("tools/list")["result"]["tools"]}
        for expected in ["list_accounts", "put_account", "put_transaction", "approve", "categorize", "delete_transactions", "assign", "move_money", "plan",
                         "put_rules", "apply_rules", "import_ynab", "compare_ynab", "schema", "sql", "changes", "undo_claude"]:
            self.assertIn(expected, names)

    def test_put_account_then_plan(self):
        self.seed()
        self.ok("assign", category_id="groc", month="2026-01", dollars="200")
        plan = self.ok("plan", month="2026-01")
        rows = [c for g in plan["groups"] for c in g["categories"]]
        self.assertEqual(next(c for c in rows if c["id"] == "groc")["assigned"], 200000)

    def test_negative_dollars_are_not_mistaken_for_options(self):
        self.seed()
        self.ok("assign", category_id="groc", month="2026-01", dollars="-5")
        self.assertEqual(self.ok("plan", month="2026-01")["readyToAssign"], 5000)

    def test_preview_changes_nothing_and_apply_then_undo(self):
        self.seed()
        self.ok("put_rule", rule={"id": "r", "name": "Groceries", "payee": {"mode": "contains", "text": "trader"}, "actions": {"categoryID": "groc", "approve": True}})
        preview = self.ok("apply_rules", preview=True)
        self.assertTrue(preview["preview"])
        self.assertEqual(len([c for c in preview["changes"] if not c.get("skipped")]), 2)
        self.assertEqual(self.ok("get_transaction", id="t0")["approved"], False)
        self.ok("apply_rules")
        self.assertEqual(self.ok("get_transaction", id="t0")["categoryID"], "groc")
        self.assertEqual(self.ok("undo_claude")["undone"], 1)
        self.assertEqual(self.ok("get_transaction", id="t0")["approved"], False)

    def test_approve_categorize_delete_with_preview(self):
        self.seed()
        self.ok("categorize", ids=["t2"], category="fun", approve=True, preview=True)
        self.assertIsNone(self.ok("get_transaction", id="t2").get("categoryID"))
        self.ok("categorize", ids=["t2"], category="fun", approve=True)
        self.assertEqual(self.ok("get_transaction", id="t2")["categoryID"], "fun")
        self.ok("delete_transactions", ids=["t0", "t1"])
        self.assertEqual(len(self.ok("list_transactions")), 1)

    def test_put_rules_keeps_order(self):
        rules = [{"id": "a", "name": "A", "actions": {"categoryID": "x"}}, {"id": "b", "name": "B", "actions": {"categoryID": "x"}}]
        self.ok("put_rules", rules=rules)
        self.assertEqual([r["id"] for r in self.ok("list_rules")], ["a", "b"])

    def test_sql_and_schema(self):
        self.seed()
        self.assertTrue(any(t["table"] == "transactions" for t in self.ok("schema")))
        rows = self.ok("sql", query="select count(*) as n from transactions")
        self.assertEqual(rows["rows"][0][0], 3)

    def test_search_runway_auto_assign_and_reconcile(self):
        self.seed()
        self.assertEqual([t["id"] for t in self.ok("search_transactions", text="movie")], ["t2"])
        self.assertEqual(len(self.ok("search_transactions", approved=False)), 3)
        self.ok("put_transaction", transaction={"id": "in", "accountID": "chk", "date": "2026-01-01", "amount": 1000000, "categoryID": "ready-to-assign", "cleared": "cleared"})
        self.ok("put_target", target={"categoryID": "groc", "amount": 400000, "cadence": {"type": "monthly", "day": 1}})
        preview = self.ok("auto_assign", month="2026-01", preview=True)
        self.assertEqual(preview["assigned"], 400000)
        self.assertEqual(self.ok("list_targets")[0]["categoryID"], "groc")
        self.ok("auto_assign", month="2026-01")
        self.assertEqual(self.ok("money_moves", month="2026-01")[0]["lines"][0]["delta"], 400000)
        self.assertEqual(self.ok("runway", month="2026-01")["months"], 2.4)
        text, err = self.tool("reconcile", account_id="chk", date="2026-01-31", balance="1.00")
        self.assertTrue(err)
        self.ok("reconcile", account_id="chk", date="2026-01-31", balance="1.00", adjust=True)

    def test_payoff_and_amazon(self):
        self.ok("put_account", account={"id": "chk", "name": "Checking"})
        self.ok("put_account", account={"id": "visa", "name": "Visa", "kind": "creditCard"})
        self.ok("put_category_group", category_group={"id": "g", "name": "G"})
        for cid in ("pets", "books"):
            self.ok("put_category", category={"id": cid, "groupID": "g", "name": cid})
        self.ok("put_transaction", transaction={"id": "amz", "accountID": "visa", "date": "2026-01-05", "amount": -30000})
        self.ok("amazon_split", transaction_id="amz", order="111-1", items=[{"name": "a", "amount": 10000, "categoryID": "pets"}, {"name": "b", "amount": 18000, "categoryID": "books"}])
        self.assertEqual(self.ok("get_amazon_order", transaction_id="amz")["tax"], 2000)
        self.assertEqual(len(self.ok("get_transaction", id="amz")["splits"]), 2)
        text, err = self.tool("payoff_plan", budget="250")
        self.assertFalse(err, text)
        self.assertIn("no APR", " ".join(json.loads(text)["warnings"]))
        self.ok("put_card_terms", account="visa", apr="0", minimum="25")
        plan = self.ok("payoff_plan", budget="250", month="2026-02")
        self.assertEqual((plan["months"], plan["debtFreeMonth"]), (1, "2026-02"))
        self.assertEqual(self.ok("list_card_terms")[0]["minimumPayment"], 25000)

    def test_errors_are_flagged(self):
        text, err = self.tool("get_account", id="nope")
        self.assertTrue(err)
        self.assertIn("not found", text)
        self.assertTrue(self.tool("no_such_tool")[1])
        self.assertTrue(self.tool("get_account")[1])


if __name__ == "__main__":
    unittest.main()
