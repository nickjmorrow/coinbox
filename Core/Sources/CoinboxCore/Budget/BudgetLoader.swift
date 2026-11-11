import Foundation
import GRDB

extension Coinbox {
    /// Everything the budget math reads, in one consistent read.
    public func budgetInput() throws -> BudgetInput {
        try db.read { db in
            BudgetInput.make(
                accounts: try Row.fetchAll(db, sql: "SELECT * FROM accounts").map(Store.decodeAccount),
                categories: try Row.fetchAll(db, sql: "SELECT * FROM categories").map(Store.decodeCategory),
                assignments: try Row.fetchAll(db, sql: "SELECT * FROM assignments").map { Assignment(categoryID: $0["category_id"], month: $0["month"], amount: $0["amount"]) },
                targets: try Row.fetchAll(db, sql: "SELECT * FROM targets").map(Store.decodeTarget),
                transactions: try Store.allTransactions(accountID: nil, db))
        }
    }

    public func calculator() throws -> BudgetCalculator { BudgetCalculator(try budgetInput()) }

    public func budget(for month: MonthKey) throws -> MonthSummary { try calculator().summary(for: month) }
}
