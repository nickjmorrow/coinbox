import CoinboxCore
import Foundation
import Testing
@testable import CoinboxUI

@MainActor private func model() throws -> AppModel {
    AppModel(coinbox: try Coinbox.inMemory(), defaults: UserDefaults(suiteName: "coinbox-test-\(UUID().uuidString)")!)
}

private let jan = MonthKey(year: 2026, month: 1)

@MainActor private func seeded() throws -> AppModel {
    let m = try model()
    m.month = jan
    m.addAccount(name: "Checking", kind: .checking, onBudget: true, startingBalance: 3_000_000, date: "2026-01-01")
    m.addAccount(name: "Visa", kind: .creditCard, onBudget: true, startingBalance: 0, date: "2026-01-01")
    m.addGroup("Bills")
    m.addCategory("Rent", in: m.groups.first { $0.name == "Bills" }!.id)
    m.addCategory("Food", in: m.groups.first { $0.name == "Bills" }!.id)
    return m
}

@MainActor @Suite struct AppModelTests {
    @Test func setMonthNoteAppearsInModel() throws {
        let m = try model()
        m.setMonthNote(month: "2026-01", text: "x")
        #expect(m.monthNotes.map(\.text) == ["x"])
        m.setMonthNote(month: "2026-01", text: "")
        #expect(m.monthNotes.isEmpty)
    }

    @Test func externalWriteIsPickedUp() throws {
        let path = NSTemporaryDirectory() + "coinbox-ui-\(UUID().uuidString)/coinbox.sqlite"
        let m = try AppModel.open(path: path)
        #expect(m.monthNotes.isEmpty)
        let other = try Coinbox.open(path: path, device: "cli")      // a second connection, like the CLI
        try other.perform([.putMonthNote(MonthNote(month: "2026-02", text: "from cli"))], author: .claude)
        #expect(m.reloadIfChanged())
        #expect(m.monthNotes.map(\.text) == ["from cli"])
        #expect(!m.reloadIfChanged())
    }

    @Test func addingAccountsGivesMoneyToAssignAndACardItsCategory() throws {
        let m = try seeded()
        #expect(m.summary.readyToAssign == 3_000_000)
        #expect(m.categories.contains { $0.id.hasPrefix("card-payment-") })
        #expect(m.cashAccounts.map(\.name) == ["Checking"] && m.creditAccounts.map(\.name) == ["Visa"])
        #expect(m.total(m.cashAccounts) == 3_000_000)
    }

    @Test func settingAssignedUpdatesReadyToAssign() throws {
        let m = try seeded()
        let rent = m.categories.first { $0.name == "Rent" }!
        m.setAssigned(rent.id, 1_200_000)
        #expect(m.summary.readyToAssign == 1_800_000 && m.summary.categories[rent.id]?.assigned == 1_200_000)
        #expect(m.moves.count == 1)
    }

    @Test func movingMoneyKeepsRTAAndIsOneUndo() throws {
        let m = try seeded()
        let rent = m.categories.first { $0.name == "Rent" }!, food = m.categories.first { $0.name == "Food" }!
        m.setAssigned(rent.id, 500_000)
        m.moveMoney(from: rent.id, to: food.id, amount: 200_000)
        #expect(m.summary.categories[rent.id]?.assigned == 300_000 && m.summary.categories[food.id]?.assigned == 200_000)
        #expect(m.summary.readyToAssign == 2_500_000)
        m.undo()
        #expect(m.summary.categories[food.id]?.assigned == 0 && m.canRedo)
        m.redo()
        #expect(m.summary.categories[food.id]?.assigned == 200_000)
    }

    @Test func autoAssignFollowsTargets() throws {
        let m = try seeded()
        let rent = m.categories.first { $0.name == "Rent" }!
        m.setTarget(Target(categoryID: rent.id, cadence: .monthly(day: 1), amount: 1_000_000), for: rent.id)
        #expect(m.summary.categories[rent.id]?.underfunded == 1_000_000)
        m.autoAssign()
        #expect(m.summary.categories[rent.id]?.underfunded == 0 && m.summary.readyToAssign == 2_000_000)
        #expect(m.runway.months == 3.0)
        m.setTarget(nil, for: rent.id)
        #expect(m.targets[rent.id] == nil)
    }

    @Test func savingATransactionCreatesThePayeeOnceAndAppliesItsDefault() throws {
        let m = try seeded()
        let chk = m.accounts.first { $0.name == "Checking" }!, food = m.categories.first { $0.name == "Food" }!
        m.save(CoinboxCore.Transaction(accountID: chk.id, date: "2026-01-05", categoryID: food.id, amount: -25_000), payeeName: "Corner Market")
        #expect(m.payees.map(\.name) == ["Corner Market"])
        var p = m.payees[0]; p.defaultCategoryID = food.id; m.save(p)
        m.save(CoinboxCore.Transaction(accountID: chk.id, date: "2026-01-06", amount: -10_000), payeeName: "corner market")
        #expect(m.payees.count == 1)
        let second = m.transactions(TransactionFilter(accountID: chk.id)).first { $0.date == "2026-01-06" }
        #expect(second?.categoryID == food.id)
        #expect(m.summary.categories[food.id]?.activity == -35_000)
    }

    @Test func aRefusedChangeSetsTheErrorAndChangesNothing() throws {
        let m = try seeded()
        let chk = m.accounts.first { $0.name == "Checking" }!
        let before = m.transactions(TransactionFilter()).count
        m.save(CoinboxCore.Transaction(accountID: chk.id, date: "2026-01-05", categoryID: CoinboxCore.Category.readyToAssignID, amount: -5_000), payeeName: "")
        #expect(m.lastError == "an outflow can't be categorized to Ready to Assign")
        #expect(m.transactions(TransactionFilter()).count == before)
    }

    @Test func approveCategorizeDeleteAndUnapprovedCount() throws {
        let m = try seeded()
        let chk = m.accounts.first { $0.name == "Checking" }!, food = m.categories.first { $0.name == "Food" }!
        m.save(CoinboxCore.Transaction(id: "a", accountID: chk.id, date: "2026-01-05", amount: -1_000, approved: false), payeeName: "")
        #expect(m.unapprovedCount == 1)
        m.categorize(["a"], to: food.id)
        #expect(m.unapprovedCount == 0 && m.summary.categories[food.id]?.activity == -1_000)
        m.delete(["a"])
        #expect(m.transactions(TransactionFilter(text: "")).filter { $0.id == "a" }.isEmpty)
    }

    @Test func reconcileThroughTheModel() throws {
        let m = try seeded()
        let chk = m.accounts.first { $0.name == "Checking" }!
        #expect(m.reconcile(accountID: chk.id, date: "2026-01-31", bankBalance: 3_000_000, adjust: false))
        #expect(m.account(chk.id)?.lastReconciledDate == "2026-01-31")
        #expect(!m.reconcile(accountID: chk.id, date: "2026-01-31", bankBalance: 2_999_000, adjust: false) && m.lastError?.contains("difference") == true)
    }

    @Test func movingACategoryReordersItsGroup() throws {
        let m = try seeded()
        let food = m.categories.first { $0.name == "Food" }!
        m.move(food, by: -1)
        let names = m.categories.filter { $0.groupID == food.groupID }.sorted { $0.order < $1.order }.map(\.name)
        #expect(names == ["Food", "Rent"])
    }

    @Test func rulesApplyAndReorder() throws {
        let m = try seeded()
        let chk = m.accounts.first { $0.name == "Checking" }!, food = m.categories.first { $0.name == "Food" }!
        m.save(Rule(id: "r1", order: 0, name: "Food", payee: TextMatch(.contains, "market"), actions: RuleActions(categoryID: food.id, approve: true)))
        m.save(Rule(id: "r2", order: 1, name: "Other", actions: RuleActions()))
        m.reorder([m.rules[1], m.rules[0]])
        #expect(m.rules.map(\.id) == ["r2", "r1"])
        m.reorder([m.rules[1], m.rules[0]])       // r2 matches everything and does nothing, so it must stay below r1
        #expect(m.rules.map(\.id) == ["r1", "r2"])
        m.save(CoinboxCore.Transaction(id: "t", accountID: chk.id, date: "2026-01-05", amount: -4_000, approved: false, rawPayee: "CORNER MARKET"), payeeName: "")
        m.applyRules()
        #expect(m.transactions(TransactionFilter()).first { $0.id == "t" }?.approved == true)
    }

    @Test func monthNavigationRecomputes() throws {
        let m = try seeded()
        let rent = m.categories.first { $0.name == "Rent" }!
        m.setAssigned(rent.id, 100_000)
        m.month = jan.next
        #expect(m.summary.categories[rent.id]?.carryover == 100_000 && m.month.title == "February 2026")
    }
}

@MainActor @Suite struct PayoffModelTests {
    @Test func termsAndPlan() throws {
        let m = try seeded()
        let visa = m.accounts.first { $0.name == "Visa" }!
        let chk = m.accounts.first { $0.name == "Checking" }!
        m.save(CoinboxCore.Transaction(accountID: visa.id, date: "2026-01-05", amount: -600_000), payeeName: "")
        #expect(m.payoff(strategy: .avalanche, monthlyBudget: 300_000)?.warnings.contains { $0.contains("no APR") } == true)
        m.setTerms(accountID: visa.id, aprPercent: 0, minimum: 25_000)
        #expect(m.cardTerms[visa.id]?.minimumPayment == 25_000)
        let plan = try #require(m.payoff(strategy: .avalanche, monthlyBudget: 300_000))
        #expect(plan.months == 2 && plan.totalInterest == 0)
        _ = chk
    }
}
