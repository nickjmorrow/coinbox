import Testing
@testable import CoinboxCore

@Suite struct MonthReviewTests {
    @Test func spendingAgainstNextMonthsPlan() throws {
        let f = try Fixture()
        try f.account("chk"); try f.category("groc"); try f.category("fun"); try f.category("idle")
        try f.c.perform([.putPayee(Payee(id: "tj", name: "Trader Joe's"))], author: .mac)
        try f.income("chk", "2026-10-01", 1000)
        try f.c.perform([.putTransaction(Transaction(id: "a", accountID: "chk", date: "2026-10-03", payeeID: "tj", categoryID: "groc", amount: usd(-60)))], author: .mac)
        try f.c.perform([.putTransaction(Transaction(id: "b", accountID: "chk", date: "2026-10-09", payeeID: "tj", categoryID: "groc", amount: usd(-40)))], author: .mac)
        try f.tx("chk", "2026-10-12", 10, "groc")                       // a refund nets against spending
        try f.tx("chk", "2026-10-15", -30, nil, splits: [SplitLine(categoryID: "groc", amount: usd(-10)), SplitLine(categoryID: "fun", amount: usd(-20))])
        try f.tx("chk", "2026-09-20", -60, "groc")                       // earlier months feed the average only
        try f.assign("groc", "2026-10", 100); try f.assign("groc", "2026-11", 80); try f.assign("fun", "2026-10", 30)

        let r = try f.c.monthReview(MonthKey("2026-10")!)
        #expect(r.month == "2026-10" && r.nextMonth == "2026-11" && r.income == usd(1000))
        let groc = try #require(r.groups.flatMap(\.categories).first { $0.categoryID == "groc" })
        #expect(groc.spent == usd(100) && groc.assigned == usd(100) && groc.nextAssigned == usd(80))
        #expect(groc.nextFunded == usd(80) && groc.planGap == usd(-20))
        #expect(groc.averageSpent == usd(160.0 / 3))
        #expect(groc.topPayees.first == PayeeSpend(name: "Trader Joe's", spent: usd(100), count: 2))
        let fun = try #require(r.groups.flatMap(\.categories).first { $0.categoryID == "fun" })
        #expect(fun.spent == usd(20) && fun.nextFunded == usd(10))      // October's leftover carries in
        #expect(!r.groups.flatMap(\.categories).contains { $0.categoryID == "idle" })   // nothing spent, nothing planned
        #expect(r.spent == usd(120) && r.nextAssigned == usd(80))
    }
}
