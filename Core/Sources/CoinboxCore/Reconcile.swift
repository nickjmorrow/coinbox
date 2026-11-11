import Foundation
import GRDB

public struct AccountBalance: Codable, Sendable, Equatable {
    /// Cleared and reconciled transactions: what the bank should say.
    public var cleared: Milliunits
    public var uncleared: Milliunits
    public var total: Milliunits { cleared + uncleared }

    public init(cleared: Milliunits, uncleared: Milliunits) { self.cleared = cleared; self.uncleared = uncleared }
}

extension Coinbox {
    public func accountBalance(accountID: String) throws -> AccountBalance { try accountBalances()[accountID] ?? AccountBalance(cleared: 0, uncleared: 0) }

    /// Every account's balance in one query.
    public func accountBalances() throws -> [String: AccountBalance] {
        try db.read { db in
            var out: [String: AccountBalance] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT account_id, cleared, SUM(amount) AS s FROM transactions GROUP BY account_id, cleared") {
                let id: String = r["account_id"]
                var b = out[id] ?? AccountBalance(cleared: 0, uncleared: 0)
                if (r["cleared"] as String) == ClearedState.uncleared.rawValue { b.uncleared += r["s"] } else { b.cleared += r["s"] }
                out[id] = b
            }
            return out
        }
    }

    /// Ops that lock an account's cleared transactions as reconciled against the bank's balance. A difference needs `adjust` (an
    /// uncategorized "Reconciliation Balance Adjustment" for the gap) or the reconcile is refused.
    public func reconcileOps(accountID: String, date: String, bankBalance: Milliunits, adjust: Bool, author: Author) throws -> [Op] {
        guard var account = try self.account(id: accountID) else { throw CoinboxError.notFound("account \(accountID)") }
        guard MonthKey.isValidDate(date) else { throw CoinboxError.invalid("date must look like 2026-01-31") }
        let cleared = try accountBalance(accountID: accountID).cleared
        let difference = bankBalance - cleared
        var ops: [Op] = []
        if difference != 0 {
            guard adjust else { throw CoinboxError.invalid("the cleared balance is \(Money.format(cleared)) but the bank says \(Money.format(bankBalance)) (difference \(Money.format(difference)))") }
            ops.append(.putTransaction(Transaction(id: "adjust-" + UUID().uuidString.lowercased(), accountID: accountID, date: date, memo: "Reconciliation Balance Adjustment",
                                                   amount: difference, cleared: .reconciled, approved: true, author: author)))
        }
        for t in try transactions(accountID: accountID) where t.cleared == .cleared { var u = t; u.cleared = .reconciled; ops.append(.putTransaction(u)) }
        account.lastReconciledDate = date
        account.lastReconciledBalance = bankBalance
        ops.append(.putAccount(account))
        return ops
    }
}
