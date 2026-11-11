import Foundation
import GRDB

enum Schema {
    static func migrator() -> DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
            CREATE TABLE month_notes (month TEXT PRIMARY KEY, text TEXT NOT NULL);
            CREATE TABLE ops (
              local_id INTEGER PRIMARY KEY AUTOINCREMENT,
              device TEXT NOT NULL,
              author TEXT NOT NULL,
              kind TEXT NOT NULL,
              payload TEXT NOT NULL,
              inverse TEXT,
              created_at INTEGER NOT NULL,
              undone_by INTEGER,
              undoes INTEGER,
              -- A change whose undo was skipped stays applied (so it keeps protecting its entities) but is not offered again.
              voided INTEGER NOT NULL DEFAULT 0,
              -- Sync: every op gets a logical timestamp; each entity remembers the newest write it has seen (last writer wins).
              ts INTEGER,
              seq INTEGER,
              origin_device TEXT,
              origin_id INTEGER,
              local INTEGER NOT NULL DEFAULT 1,
              pushed INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX ops_seq ON ops(seq);
            CREATE UNIQUE INDEX ops_origin ON ops(origin_device, origin_id);
            CREATE TABLE clocks (entity TEXT PRIMARY KEY, ts INTEGER NOT NULL, device TEXT NOT NULL);
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
        }
        m.registerMigration("v2") { db in
            try db.execute(sql: """
            CREATE TABLE accounts (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, on_budget INTEGER NOT NULL, closed INTEGER NOT NULL,
              note TEXT, simplefin_id TEXT, ynab_id TEXT, last_reconciled_date TEXT, last_reconciled_balance INTEGER
            );
            CREATE TABLE category_groups (id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL, hidden INTEGER NOT NULL);
            CREATE TABLE categories (
              id TEXT PRIMARY KEY, group_id TEXT NOT NULL, name TEXT NOT NULL, position INTEGER NOT NULL, hidden INTEGER NOT NULL,
              note TEXT, kind TEXT NOT NULL, card_account_id TEXT, ynab_id TEXT
            );
            CREATE UNIQUE INDEX categories_card ON categories(card_account_id) WHERE card_account_id IS NOT NULL;
            CREATE TABLE payees (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, default_category_id TEXT, default_locked INTEGER NOT NULL, transfer_account_id TEXT
            );
            CREATE TABLE assignments (
              category_id TEXT NOT NULL, month TEXT NOT NULL, amount INTEGER NOT NULL, PRIMARY KEY (category_id, month)
            );
            CREATE TABLE targets (category_id TEXT PRIMARY KEY, cadence TEXT NOT NULL, amount INTEGER NOT NULL);
            CREATE TABLE transactions (
              id TEXT PRIMARY KEY, account_id TEXT NOT NULL, date TEXT NOT NULL, payee_id TEXT, category_id TEXT, memo TEXT,
              amount INTEGER NOT NULL, cleared TEXT NOT NULL, approved INTEGER NOT NULL, transfer_pair_id TEXT,
              bank_import_id TEXT, ynab_id TEXT, pending INTEGER NOT NULL, author TEXT NOT NULL
            );
            CREATE INDEX transactions_account_date ON transactions(account_id, date);
            CREATE INDEX transactions_ynab ON transactions(ynab_id);
            CREATE INDEX transactions_bank ON transactions(bank_import_id);
            CREATE TABLE split_lines (
              transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
              position INTEGER NOT NULL, category_id TEXT NOT NULL, amount INTEGER NOT NULL, memo TEXT,
              PRIMARY KEY (transaction_id, position)
            );
            -- Built-in rows have fixed ids and are inserted here, not as ops, so every device has them.
            INSERT INTO category_groups (id, name, position, hidden) VALUES ('inflow', 'Inflow', -2, 0), ('card-payments', 'Credit Card Payments', -1, 0);
            INSERT INTO categories (id, group_id, name, position, hidden, kind) VALUES
              ('ready-to-assign', 'inflow', 'Ready to Assign', 0, 0, 'readyToAssign'),
              ('card-interest', 'card-payments', 'Interest & Fees', 1000, 0, 'cardInterest');
            """)
        }
        m.registerMigration("v3") { db in
            try db.execute(sql: """
            ALTER TABLE transactions ADD COLUMN raw_payee TEXT;
            CREATE TABLE rules (id TEXT PRIMARY KEY, position INTEGER NOT NULL, body TEXT NOT NULL);
            """)
        }
        m.registerMigration("v4") { db in
            try db.execute(sql: """
            CREATE TABLE card_terms (account_id TEXT PRIMARY KEY, apr_basis_points INTEGER NOT NULL, minimum_payment INTEGER NOT NULL);
            CREATE TABLE amazon_links (transaction_id TEXT PRIMARY KEY, body TEXT NOT NULL);
            """)
        }
        return m
    }
}
