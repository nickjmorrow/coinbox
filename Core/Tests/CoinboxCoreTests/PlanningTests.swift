import Testing
@testable import CoinboxCore

@Suite struct PlanningTests {
    private func setup() throws -> Fixture {
        let f = try Fixture()
        try f.account("chk"); try f.account("sav", .savings); try f.account("visa", .creditCard); try f.category("rent"); try f.category("groc"); try f.category("fun")
        return f
    }

    // Reconcile

    @Test func balancesSplitByClearedState() throws {
        let f = try setup()
        try f.c.perform([.putTransaction(Transaction(id: "a", accountID: "chk", date: "2026-01-02", amount: 100_000, cleared: .cleared)),
                         .putTransaction(Transaction(id: "b", accountID: "chk", date: "2026-01-03", amount: -30_000, cleared: .uncleared)),
                         .putTransaction(Transaction(id: "c", accountID: "chk", date: "2026-01-04", amount: -5_000, cleared: .reconciled))], author: .mac)
        #expect(try f.c.accountBalance(accountID: "chk") == AccountBalance(cleared: 95_000, uncleared: -30_000))
        #expect(try f.c.accountBalance(accountID: "chk").total == 65_000 && (try f.c.accountBalance(accountID: "sav")) == AccountBalance(cleared: 0, uncleared: 0))
    }

    @Test func reconcileLocksClearedRowsWhenTheBalanceMatches() throws {
        let f = try setup()
        try f.c.perform([.putTransaction(Transaction(id: "a", accountID: "chk", date: "2026-01-02", amount: 100_000, cleared: .cleared)),
                         .putTransaction(Transaction(id: "b", accountID: "chk", date: "2026-01-03", amount: -30_000, cleared: .uncleared))], author: .mac)
        try f.c.perform(try f.c.reconcileOps(accountID: "chk", date: "2026-01-31", bankBalance: 100_000, adjust: false, author: .mac), author: .mac)
        #expect(try f.c.transaction(id: "a")?.cleared == .reconciled && (try f.c.transaction(id: "b")?.cleared) == .uncleared)
        let a = try #require(try f.c.account(id: "chk"))
        #expect(a.lastReconciledDate == "2026-01-31" && a.lastReconciledBalance == 100_000)
    }

    @Test func aDifferenceIsRefusedUnlessAdjusting() throws {
        let f = try setup()
        try f.c.perform([.putTransaction(Transaction(id: "a", accountID: "chk", date: "2026-01-02", amount: 100_000, cleared: .cleared))], author: .mac)
        do { _ = try f.c.reconcileOps(accountID: "chk", date: "2026-01-31", bankBalance: 99_000, adjust: false, author: .mac); Issue.record("expected a throw") }
        catch let e as CoinboxError { #expect(e.message.contains("difference -$1.00")) }
        try f.c.perform(try f.c.reconcileOps(accountID: "chk", date: "2026-01-31", bankBalance: 99_000, adjust: true, author: .mac), author: .mac)
        #expect(try f.c.accountBalance(accountID: "chk") == AccountBalance(cleared: 99_000, uncleared: 0))
        #expect(try f.c.transactions().contains { $0.memo == "Reconciliation Balance Adjustment" && $0.amount == -1_000 })
    }

    @Test func reconcileIsOneUndoableChange() throws {
        let f = try setup()
        try f.c.perform([.putTransaction(Transaction(id: "a", accountID: "chk", date: "2026-01-02", amount: 100_000, cleared: .cleared))], author: .mac)
        try f.c.perform(try f.c.reconcileOps(accountID: "chk", date: "2026-01-31", bankBalance: 100_000, adjust: false, author: .mac), author: .mac)
        try f.c.undo()
        #expect(try f.c.transaction(id: "a")?.cleared == .cleared && (try f.c.account(id: "chk")?.lastReconciledDate) == nil)
    }

    // Auto-assign

    @Test func autoAssignFillsUnderfundedInPlanOrder() throws {
        let f = try setup()
        try f.income("chk", "2026-01-01", 1000)
        try f.c.perform([.putTarget(Target(categoryID: "rent", cadence: .monthly(day: 1), amount: usd(600))), .putTarget(Target(categoryID: "groc", cadence: .monthly(day: 1), amount: usd(300)))], author: .mac)
        let r = try f.c.autoAssignOps(month: MonthKey("2026-01")!)
        #expect(r.assigned == usd(900) && r.readyToAssignLeft == usd(100))
        try f.c.perform(r.ops, author: .claude)
        #expect(try f.summary("2026-01").categories["rent"]?.underfunded == 0 && (try f.summary("2026-01").readyToAssign) == usd(100))
    }

    @Test func autoAssignStopsWhenTheMoneyRunsOut() throws {
        let f = try setup()
        try f.income("chk", "2026-01-01", 700)
        try f.c.perform([.putTarget(Target(categoryID: "rent", cadence: .monthly(day: 1), amount: usd(600))), .putTarget(Target(categoryID: "groc", cadence: .monthly(day: 1), amount: usd(300)))], author: .mac)
        let r = try f.c.autoAssignOps(month: MonthKey("2026-01")!)
        #expect(r.assigned == usd(700) && r.readyToAssignLeft == 0)
        try f.c.perform(r.ops, author: .claude)
        #expect(try f.summary("2026-01").readyToAssign == 0)
    }

    @Test func autoAssignWithNothingToDoIsEmpty() throws {
        let f = try setup()
        #expect(try f.c.autoAssignOps(month: MonthKey("2026-01")!).ops.isEmpty)
    }

    // Runway

    @Test func runwayIsCashOverCostToBeMe() throws {
        let f = try setup()
        try f.income("chk", "2026-01-01", 5000); try f.income("sav", "2026-01-01", 1000)
        try f.tx("visa", "2026-01-02", -400)
        try f.c.perform([.putTarget(Target(categoryID: "rent", cadence: .monthly(day: 1), amount: usd(1500))), .putTarget(Target(categoryID: "groc", cadence: .monthly(day: 1), amount: usd(500)))], author: .mac)
        let r = try f.c.runway(asOf: MonthKey("2026-01")!)
        #expect(r.cash == usd(6000) && r.costToBeMe == usd(2000) && r.months == 3.0)
    }

    @Test func runwayRoundsToOneDecimalAndIsNilWithoutTargets() throws {
        let f = try setup()
        try f.income("chk", "2026-01-01", 1000)
        #expect(try f.c.runway(asOf: MonthKey("2026-01")!).months == nil)
        try f.c.perform([.putTarget(Target(categoryID: "rent", cadence: .monthly(day: 1), amount: usd(300)))], author: .mac)
        #expect(try f.c.runway(asOf: MonthKey("2026-01")!).months == 3.3)
    }

    // Money moves

    @Test func moneyMovesShowDeltasFromTheChangeLog() throws {
        let f = try setup()
        try f.assign("rent", "2026-01", 500)
        try f.c.perform([.putAssignment(Assignment(categoryID: "rent", month: "2026-01", amount: usd(400))), .putAssignment(Assignment(categoryID: "fun", month: "2026-01", amount: usd(100)))], author: .claude)
        try f.assign("groc", "2026-02", 50)
        let moves = try f.c.moneyMoves(month: "2026-01")
        #expect(moves.count == 2)
        #expect(moves[0].author == .claude && Set(moves[0].lines) == [.init(categoryID: "rent", delta: usd(-100)), .init(categoryID: "fun", delta: usd(100))])
        #expect(moves[1].lines == [.init(categoryID: "rent", delta: usd(500))])
        #expect(try f.c.moneyMoves(month: "2026-03").isEmpty)
    }

    @Test func anUndoneMoveIsFlaggedAndItsUndoIsNotListedAsAMove() throws {
        let f = try setup()
        try f.assign("rent", "2026-01", 500)
        try f.c.undo()
        let moves = try f.c.moneyMoves(month: "2026-01")
        #expect(moves.count == 1 && moves[0].undone)
    }

    // Search

    @Test func searchFiltersCombine() throws {
        let f = try setup()
        try f.c.perform([.putPayee(Payee(id: "p", name: "Trader Joe's"))], author: .mac)
        try f.c.perform([.putTransaction(Transaction(id: "a", accountID: "chk", date: "2026-01-05", payeeID: "p", categoryID: "groc", memo: "weekly", amount: -42_000)),
                         .putTransaction(Transaction(id: "b", accountID: "chk", date: "2026-02-05", categoryID: "fun", amount: -9_000, approved: false, rawPayee: "MOVIE THEATRE")),
                         .putTransaction(Transaction(id: "c", accountID: "visa", date: "2026-02-06", amount: -1_000, approved: false))], author: .mac)
        func ids(_ f2: TransactionFilter) throws -> [String] { try f.c.search(f2).map(\.id) }
        #expect(try ids(TransactionFilter(text: "joe")) == ["a"])
        #expect(try ids(TransactionFilter(text: "theatre")) == ["b"])
        #expect(try ids(TransactionFilter(text: "$42.00")) == ["a"])
        #expect(try ids(TransactionFilter(approved: false)) == ["c", "b"])
        #expect(try ids(TransactionFilter(accountID: "chk", from: "2026-02-01")) == ["b"])
        #expect(try ids(TransactionFilter(categoryID: "groc")) == ["a"])
        #expect(try ids(TransactionFilter(uncategorized: true)) == ["c"])
        #expect(try ids(TransactionFilter()) == ["c", "b", "a"])
    }

    @Test func searchFindsSplitCategories() throws {
        let f = try setup()
        try f.tx("chk", "2026-01-05", -50, id: "s", splits: [SplitLine(categoryID: "groc", amount: usd(-30)), SplitLine(categoryID: "fun", amount: usd(-20))])
        #expect(try f.c.search(TransactionFilter(categoryID: "fun")).map(\.id) == ["s"])
    }
}

@Suite struct RedoTests {
    @Test func redoPutsTheUndoneChangeBack() throws {
        let c = try Coinbox.inMemory()
        try c.perform([.putMonthNote(note("2026-01", "a"))], author: .mac)
        #expect(try !c.canRedo())
        try c.undo()
        #expect(try c.monthNote("2026-01") == nil && (try c.canRedo()))
        try c.redo(author: .mac)
        #expect(try c.monthNote("2026-01")?.text == "a" && (try !c.canRedo()))
    }

    @Test func redoWithNothingUndoneDoesNothing() throws {
        let c = try Coinbox.inMemory()
        try c.perform([.putMonthNote(note("2026-01", "a"))], author: .mac)
        #expect(try c.redo(author: .mac) == nil)
    }

    @Test func aNewEditAfterUndoEndsRedo() throws {
        let c = try Coinbox.inMemory()
        try c.perform([.putMonthNote(note("2026-01", "a"))], author: .mac)
        try c.undo()
        try c.perform([.putMonthNote(note("2026-02", "b"))], author: .mac)
        #expect(try !c.canRedo())
    }
}
