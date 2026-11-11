import Testing
@testable import CoinboxCore

@Suite struct YNABMapperTests {
    private func desired() -> YNABDesired { YNABMapper.map(YNABFixture.snapshot(), since: "2026-01-01", options: YNABOptions(interestCategoryName: "Interest & Fees")) }

    @Test func idsAreDeterministic() {
        #expect(desired().accounts.map(\.id) == YNABMapper.map(YNABFixture.snapshot(), since: "2026-01-01").accounts.map(\.id))
        #expect(desired().accounts.first?.id == "ynab-a-chk")
    }

    @Test func accountTypesMap() {
        let kinds = Dictionary(uniqueKeysWithValues: desired().accounts.map { ($0.id, $0.kind) })
        #expect(kinds["ynab-a-visa"] == .creditCard && kinds["ynab-a-mort"] == .mortgage && kinds["ynab-a-sav"] == .savings)
        #expect(desired().accounts.first { $0.id == "ynab-a-mort" }?.onBudget == false)
        #expect(YNABMapper.kind(of: YNABAccount(id: "x", name: "x", type: "studentLoan", onBudget: false)) == .loan)
        #expect(YNABMapper.kind(of: YNABAccount(id: "x", name: "x", type: "otherAsset", onBudget: false)) == .asset)
    }

    @Test func cardPaymentCategoryMapsToCardAccount() {
        let p = desired().categories.first { $0.id == "card-payment-ynab-a-visa" }
        #expect(p?.kind == .cardPayment(accountID: "ynab-a-visa") && p?.ynabID == "c-ccp")
    }

    @Test func rtaAndInterestMapToBuiltIns() {
        let d = desired()
        #expect(d.categories.first { $0.id == Category.readyToAssignID }?.ynabID == "c-rta")
        #expect(d.categories.first { $0.id == Category.cardInterestID }?.ynabID == "c-int")
        #expect(!d.categories.contains { $0.id == "ynab-c-unc" || $0.id == "ynab-c-gone" || $0.id == "ynab-c-rta" })
        #expect(!d.groups.contains { $0.name == "Internal Master Category" || $0.name == "Credit Card Payments" })
        #expect(d.groups.first { $0.name == "Fun" }?.hidden == true)
    }

    @Test func interestAndFeesIsAnOrdinaryCategoryByDefault() {
        let d = YNABMapper.map(YNABFixture.snapshot(), since: "2026-01-01")
        #expect(d.categories.contains { $0.id == "ynab-c-int" && $0.kind == .normal })
        #expect(d.categories.first { $0.id == Category.cardInterestID }?.ynabID == nil)
    }

    @Test func startingBalanceTransactions() throws {
        let d = desired()
        func start(_ a: String) -> Transaction? { d.transactions.first { $0.id == "ynab-start-\(a)" } }
        #expect(start("a-chk")?.amount == 1_000_000 && start("a-chk")?.categoryID == Category.readyToAssignID && start("a-chk")?.date == "2025-12-31")
        #expect(start("a-sav")?.amount == 1_000_000 && start("a-sav")?.categoryID == Category.readyToAssignID)
        #expect(start("a-visa")?.amount == -500_000 && start("a-visa")?.categoryID == nil)
        #expect(start("a-mort")?.amount == -200_000_000 && start("a-mort")?.categoryID == nil)
        #expect(d.report.warnings.contains { $0.contains("not funded") && $0.contains("Visa") })
    }

    @Test func openingAssignmentsFromFirstMonth() {
        let d = desired()
        #expect(d.assignments.contains(Assignment(categoryID: "ynab-c-fun", month: "2025-12", amount: 190_000)))
        #expect(d.assignments.contains(Assignment(categoryID: "ynab-c-rent", month: "2026-01", amount: 1_300_000)))
        #expect(!d.assignments.contains { $0.categoryID == "ynab-c-rent" && $0.month == "2025-12" })     // carryover 0
    }

    @Test func negativeRTARowImportedUncategorizedAndListed() {
        let d = desired()
        #expect(d.transactions.first { $0.id == "ynab-t11" }?.categoryID == nil)
        #expect(d.report.warnings.contains { $0.contains("Ready to Assign") })
    }

    @Test func splitsImportedAndUncategorizedPartFallsBackToUnsplit() {
        let d = desired()
        #expect(d.transactions.first { $0.id == "ynab-t12" }?.splits.count == 2)
        #expect(d.transactions.first { $0.id == "ynab-t14" }?.splits.isEmpty == true)
        #expect(d.report.warnings.contains { $0.contains("imported unsplit") })
    }

    @Test func deletedTransactionsAndPayeesSkipped() {
        let d = desired()
        #expect(!d.transactions.contains { $0.id == "ynab-t10" })
        #expect(!d.payees.contains { $0.name == "Gone" })
        #expect(d.payees.first { $0.name == "Transfer : Savings" }?.transferAccountID == "ynab-a-sav")
    }

    @Test func transfersKeepTheirPairs() {
        let d = desired()
        #expect(d.transactions.first { $0.id == "ynab-t4" }?.transferPairID == "ynab-t5")
        #expect(d.transactions.first { $0.id == "ynab-t9" }?.categoryID == nil)
        #expect(d.transactions.first { $0.id == "ynab-t8" }?.categoryID == "ynab-c-rent")
    }

    @Test func goalMapping() {
        let t = Dictionary(uniqueKeysWithValues: desired().targets.map { ($0.categoryID, $0) })
        #expect(t["ynab-c-rent"]?.cadence == .monthly(day: 1) && t["ynab-c-rent"]?.amount == 1_300_000)
        #expect(t["ynab-c-phone"]?.cadence == .monthly(day: 5))
        #expect(t["ynab-c-car"]?.cadence == .weekly(isoWeekday: 7))
        #expect(t["ynab-c-ins"]?.cadence == .yearly(month: 12, day: 15))
        #expect(t["ynab-c-trip"]?.cadence == .byDate("2026-06-30"))
        #expect(t["ynab-c-tb"] == nil)
        #expect(desired().report.warnings.contains { $0.contains("Cushion") })
    }

    @Test func monthNotesImported() {
        #expect(desired().monthNotes == [MonthNote(month: "2026-01", text: "tight")])
    }

    @Test func dayBefore() {
        #expect(MonthKey.dayBefore("2026-01-01") == "2025-12-31")
        #expect(MonthKey.dayBefore("2026-03-01") == "2026-02-28")
        #expect(MonthKey.dayBefore("2026-03-15") == "2026-03-14")
    }
}
