import Testing
@testable import CoinboxCore

@Suite struct EntityOpsTests {
    @Test func builtInRowsExist() throws {
        let c = try Coinbox.inMemory()
        #expect(try c.category(id: "ready-to-assign")?.kind == .readyToAssign)
        #expect(try c.category(id: "card-interest")?.kind == .cardInterest)
        #expect(try c.categoryGroup(id: "inflow") != nil && (try c.categoryGroup(id: "card-payments")) != nil)
    }

    @Test func putAndReadEach() throws {
        let c = try Coinbox.inMemory()
        let a = Account(id: "a", name: "Chase", kind: .savings, note: "n", ynabID: "y", lastReconciledDate: "2026-01-31", lastReconciledBalance: 5_000)
        let g = CategoryGroup(id: "g", name: "Bills", order: 3, hidden: true)
        let cat = Category(id: "c", groupID: "g", name: "Rent", order: 2, note: "n", ynabID: "yc")
        let p = Payee(id: "p", name: "Landlord", defaultCategoryID: "c", defaultLocked: true)
        let asg = Assignment(categoryID: "c", month: "2026-01", amount: 1_500_000)
        let t = Target(categoryID: "c", cadence: .everyMonths(n: 3, firstDue: "2026-03-31"), amount: 90_000)
        try c.perform([.putAccount(a), .putCategoryGroup(g), .putCategory(cat), .putPayee(p), .putAssignment(asg), .putTarget(t)], author: .mac)
        #expect(try c.account(id: "a") == a)
        #expect(try c.categoryGroup(id: "g") == g)
        #expect(try c.category(id: "c") == cat)
        #expect(try c.payee(id: "p") == p)
        #expect(try c.assignment(categoryID: "c", month: "2026-01") == asg)
        #expect(try c.target(categoryID: "c") == t)
        #expect(try c.accounts() == [a] && (try c.targets()) == [t] && (try c.assignments()) == [asg])
    }

    @Test func undoOfPutAccountDeletesIt() throws {
        let c = try Coinbox.inMemory()
        try c.perform([.putAccount(Account(id: "a", name: "A"))], author: .claude)
        try c.undo(author: .claude)
        #expect(try c.account(id: "a") == nil)
    }

    @Test func assignmentUndoRestoresPreviousAmount() throws {
        let f = try Fixture()
        let cat = try f.category("groc")
        try f.assign(cat, "2026-01", 100)
        try f.assign(cat, "2026-01", 250)
        try f.c.undo()
        #expect(try f.c.assignment(categoryID: cat, month: "2026-01")?.amount == usd(100))
    }

    @Test func deleteCategoryWithAssignmentThrowsHasHistory() throws {
        let f = try Fixture()
        let cat = try f.category("groc")
        try f.assign(cat, "2026-01", 1)
        do { try f.c.perform([.deleteCategory(id: cat)], author: .mac); Issue.record("expected a throw") }
        catch let e as CoinboxError { guard case .hasHistory = e else { Issue.record("wrong error \(e)"); return } }
    }

    @Test func deleteGroupWithCategoriesIsRefused() throws {
        let f = try Fixture()
        try f.category("groc")
        do { try f.c.perform([.deleteCategoryGroup(id: "g")], author: .mac); Issue.record("expected a throw") }
        catch let e as CoinboxError { guard case .hasHistory = e else { Issue.record("wrong error \(e)"); return } }
    }

    @Test func assignToReadyToAssignIsInvalid() throws {
        let c = try Coinbox.inMemory()
        #expect(throws: CoinboxError.self) {
            try c.perform([.putAssignment(Assignment(categoryID: "ready-to-assign", month: "2026-01", amount: 1))], author: .mac)
        }
    }

    @Test func badMonthIsInvalid() throws {
        let f = try Fixture()
        let cat = try f.category("groc")
        #expect(throws: CoinboxError.invalid("month must look like 2026-01")) {
            try f.c.perform([.putAssignment(Assignment(categoryID: cat, month: "2026-1", amount: 1))], author: .mac)
        }
    }

    @Test func secondPaymentCategoryForOneCardFails() throws {
        let c = try Coinbox.inMemory()
        try c.perform([.putCategory(Category(id: "p1", groupID: "card-payments", name: "P1", kind: .cardPayment(accountID: "a")))], author: .mac)
        #expect(throws: (any Error).self) {
            try c.perform([.putCategory(Category(id: "p2", groupID: "card-payments", name: "P2", kind: .cardPayment(accountID: "a")))], author: .mac)
        }
    }
}
