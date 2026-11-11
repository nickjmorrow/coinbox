import Foundation
import Testing
@testable import CoinboxCore

@Suite struct BudgetLoaderTests {
    @Test func loaderMatchesHandBuiltInput() throws {
        let f = try Fixture()
        try f.account("chk"); try f.category("groc"); try f.income("chk", "2026-01-02", 100); try f.assign("groc", "2026-01", 40); try f.tx("chk", "2026-01-04", -10, "groc")
        let hand = BudgetInput.make(accounts: try f.c.accounts(), categories: try f.c.categories(), assignments: try f.c.assignments(),
                                    targets: try f.c.targets(), transactions: try f.c.transactions())
        #expect(try f.c.budget(for: MonthKey("2026-01")!) == BudgetCalculator(hand).summary(for: MonthKey("2026-01")!))
    }

    @Test func splitTransactionIsFlattenedByCategory() throws {
        let f = try Fixture()
        try f.account("chk"); try f.category("groc"); try f.category("fun")
        try f.tx("chk", "2026-01-04", -50, id: "s", splits: [SplitLine(categoryID: "groc", amount: usd(-30)), SplitLine(categoryID: "fun", amount: usd(-20))])
        let s = try f.summary("2026-01")
        #expect(s.categories["groc"]?.activity == usd(-30) && s.categories["fun"]?.activity == usd(-20))
    }

    @Test func largeBudgetComputesQuickly() throws {
        let c = try Coinbox.inMemory()
        var ops: [Op] = [.putAccount(Account(id: "chk", name: "chk")), .putCategoryGroup(CategoryGroup(id: "g", name: "g"))]
        for i in 0..<40 { ops.append(.putCategory(Category(id: "c\(i)", groupID: "g", name: "c\(i)"))) }
        for n in 0..<6000 {
            let month = MonthKey(year: 2026, month: 1).adding(months: n % 24)
            ops.append(.putTransaction(Transaction(id: "t\(n)", accountID: "chk", date: month.firstDay.dropLast(2) + String(format: "%02d", 1 + n % 27), categoryID: "c\(n % 40)", amount: -1_000)))
        }
        try c.perform(ops, author: .importer)
        let start = Date()
        let s = try c.budget(for: MonthKey("2027-12")!)
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(s.categories.count >= 40)
    }
}
