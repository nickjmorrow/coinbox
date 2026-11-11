import Testing
@testable import CoinboxCore

@Suite struct YNABImporterTests {
    private func run(_ s: YNABSnapshot, into c: Coinbox, plug: Bool = false) throws -> [Op] {
        let options = YNABOptions(interestCategoryName: "Interest & Fees", plugOpeningRTA: plug)
        var d = YNABMapper.map(s, since: "2026-01-01", options: options)
        try YNABImporter.finalize(&d, snapshot: s, since: "2026-01-01", options: options, today: "2026-01-15")
        let ops = try c.planYNABImport(d)
        try c.applyYNABImport(ops)
        return ops
    }

    @Test func secondRunProducesNoOps() throws {
        let c = try Coinbox.inMemory()
        #expect(try !run(YNABFixture.snapshot(), into: c).isEmpty)
        #expect(try run(YNABFixture.snapshot(), into: c).isEmpty)
    }

    @Test func changedAmountProducesExactlyOneOp() throws {
        let c = try Coinbox.inMemory()
        _ = try run(YNABFixture.snapshot(), into: c)
        var s = YNABFixture.snapshot()
        let i = try #require(s.transactions.firstIndex { $0.id == "t2" })
        s.transactions[i].amount -= 5_000
        s.accounts[0].balance -= 5_000          // the account balance moves with it, so the starting balance stays put
        let ops = try run(s, into: c)
        #expect(ops.count == 1)
        if case let .putTransaction(t) = ops[0] { #expect(t.id == "ynab-t2" && t.amount == -1_005_000) } else { Issue.record("expected a transaction put") }
    }

    @Test func ynabDeletedTransactionIsDeleted() throws {
        let c = try Coinbox.inMemory()
        _ = try run(YNABFixture.snapshot(), into: c)
        var s = YNABFixture.snapshot()
        let i = try #require(s.transactions.firstIndex { $0.id == "t3" })
        s.transactions[i].deleted = true
        s.accounts[1].balance += 120_000
        let ops = try run(s, into: c)
        #expect(ops.contains(.deleteTransaction(id: "ynab-t3")))
        #expect(try c.transaction(id: "ynab-t3") == nil)
    }

    @Test func manualTransactionsAreLeftAlone() throws {
        let c = try Coinbox.inMemory()
        _ = try run(YNABFixture.snapshot(), into: c)
        try c.perform([.putTransaction(Transaction(id: "mine", accountID: "ynab-a-chk", date: "2026-01-02", amount: -1))], author: .mac)
        #expect(try run(YNABFixture.snapshot(), into: c).isEmpty)
        #expect(try c.transaction(id: "mine") != nil)
    }

    @Test func importedBudgetMatchesYNABNumbers() throws {
        let c = try Coinbox.inMemory()
        _ = try run(YNABFixture.snapshot(), into: c)
        #expect(try c.compareToYNAB(YNABFixture.snapshot(), today: "2026-01-15") == [])
    }

    @Test func compareFlagsOneMilliunit() throws {
        let c = try Coinbox.inMemory()
        _ = try run(YNABFixture.snapshot(), into: c)
        var s = YNABFixture.snapshot()
        s.months[0].categories[0].activity += 1
        let diffs = try c.compareToYNAB(s, today: "2026-01-15")
        #expect(diffs == [YNABDifference(scope: "2026-01", subject: "Rent: activity", ynab: -1_329_999, coinbox: -1_330_000)])
    }

    @Test func openingPlugClosesARTAGap() throws {
        var s = YNABFixture.snapshot()
        s.months[0].toBeBudgeted = 4_000_000      // YNAB had 590,000 more than the rebuilt history explains
        let without = try Coinbox.inMemory()
        _ = try run(s, into: without)
        #expect(try without.compareToYNAB(s, today: "2026-01-15").map(\.subject) == ["Ready to Assign"])
        let with = try Coinbox.inMemory()
        _ = try run(s, into: with, plug: true)
        #expect(try with.compareToYNAB(s, today: "2026-01-15") == [])
    }

    @Test func gapIsAlwaysInTheReport() throws {
        var s = YNABFixture.snapshot()
        s.months[0].toBeBudgeted = 4_000_000
        var d = YNABMapper.map(s, since: "2026-01-01")
        try YNABImporter.finalize(&d, snapshot: s, since: "2026-01-01", options: YNABOptions(), today: "2026-01-15")
        #expect(d.report.warnings.contains { $0.contains("Ready to Assign for 2026-01") && $0.contains("$590.00") })
    }

    @Test func planningWritesNothing() throws {
        let c = try Coinbox.inMemory()
        _ = try c.planYNABImport(YNABMapper.map(YNABFixture.snapshot(), since: "2026-01-01"))
        #expect(try c.transactions().isEmpty && (try c.accounts()).isEmpty)
    }

    @Test func compareReportsAMissingAccount() throws {
        let c = try Coinbox.inMemory()
        let diffs = try c.compareToYNAB(YNABSnapshot(accounts: [YNABAccount(id: "z", name: "Zed", type: "checking", balance: 5)]))
        #expect(diffs.first?.subject == "Zed: missing here")
    }
}

@Suite struct YNABReferenceMonthTests {
    @Test func thePluggedMonthIsThisMonthWhenYNABHasIt() {
        let s = YNABSnapshot(months: [YNABMonth(month: "2026-08-01"), YNABMonth(month: "2026-09-01"), YNABMonth(month: "2026-11-01"), YNABMonth(month: "2026-12-01")])
        #expect(YNABImporter.referenceMonth(s, today: "2026-11-02") == MonthKey("2026-11"))
        #expect(YNABImporter.referenceMonth(s, today: "2026-10-15") == MonthKey("2026-09"))      // no October in the snapshot: the latest before it
        #expect(YNABImporter.referenceMonth(s, today: "2026-07-01") == MonthKey("2026-08"))
    }

    @Test func pastMonthsReadyToAssignIsNotCompared() throws {
        let c = try Coinbox.inMemory()
        var s = YNABFixture.snapshot()
        s.months[0].toBeBudgeted = 1
        var d = YNABMapper.map(s, since: "2026-01-01")
        try YNABImporter.finalize(&d, snapshot: s, since: "2026-01-01", options: YNABOptions(plugOpeningRTA: true), today: "2026-02-10")
        try c.applyYNABImport(try c.planYNABImport(d))
        #expect(try c.compareToYNAB(s, today: "2026-02-10").filter { $0.subject == "Ready to Assign" }.isEmpty)
    }
}
