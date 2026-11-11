import Foundation
@testable import CoinboxCore

/// Dollars to milliunits, rounded.
func usd(_ dollars: Double) -> Milliunits { Milliunits((dollars * 1000).rounded()) }

/// A small in-memory budget for tests. Ids are the names given, so tests read like the scenarios in the plan.
final class Fixture {
    let c: Coinbox
    private var seq = 0

    init() throws {
        c = try Coinbox.inMemory()
        try c.perform([.putCategoryGroup(CategoryGroup(id: "g", name: "Spending"))], author: .mac)
    }

    @discardableResult
    func account(_ id: String, _ kind: AccountKind = .checking, onBudget: Bool? = nil, closed: Bool = false) throws -> String {
        let tracking = [.mortgage, .loan, .asset].contains(kind)
        try c.perform(Coinbox.createAccountOps(Account(id: id, name: id, kind: kind, onBudget: onBudget ?? !tracking, closed: closed)), author: .mac)
        return id
    }

    @discardableResult
    func category(_ id: String, hidden: Bool = false) throws -> String {
        try c.perform([.putCategory(Category(id: id, groupID: "g", name: id, hidden: hidden))], author: .mac)
        return id
    }

    func assign(_ category: String, _ month: String, _ dollars: Double) throws {
        try c.perform([.putAssignment(Assignment(categoryID: category, month: month, amount: usd(dollars)))], author: .mac)
    }

    /// Records a transaction; `dollars` is signed (negative = outflow).
    @discardableResult
    func tx(_ account: String, _ date: String, _ dollars: Double, _ category: String? = nil, id: String? = nil, splits: [SplitLine] = []) throws -> String {
        seq += 1
        let txID = id ?? "t\(seq)"
        try c.perform([.putTransaction(Transaction(id: txID, accountID: account, date: date, categoryID: category, amount: usd(dollars), splits: splits))], author: .mac)
        return txID
    }

    func income(_ account: String, _ date: String, _ dollars: Double) throws { try tx(account, date, dollars, Category.readyToAssignID) }

    func transfer(_ from: String, _ to: String, _ date: String, _ dollars: Double, category: String? = nil) throws {
        seq += 1
        try c.perform(try c.transferOps(id: "x\(seq)", date: date, from: from, to: to, amount: usd(dollars), categoryID: category, author: .mac), author: .mac)
    }

    func summary(_ month: String) throws -> MonthSummary { try c.budget(for: MonthKey(month)!) }
}
