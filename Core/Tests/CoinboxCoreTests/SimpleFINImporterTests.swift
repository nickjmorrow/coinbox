import Foundation
import Testing
@testable import CoinboxCore

@Suite struct SimpleFINImporterTests {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-01-05 12:00 UTC
    private let jan5: Int64 = 1_767_614_400
    private func day(_ n: Int) -> Int64 { jan5 + Int64(n) * 86_400 }

    private func setup() throws -> Fixture {
        let f = try Fixture()
        try f.c.perform(Coinbox.createAccountOps(Account(id: "chk", name: "Checking", simplefinID: "ACT-CHK")), author: .mac)
        try f.c.perform(Coinbox.createAccountOps(Account(id: "visa", name: "Visa", kind: .creditCard, simplefinID: "ACT-VISA")), author: .mac)
        try f.category("groc")
        return f
    }

    private func response(chk: [SFTransaction] = [], visa: [SFTransaction] = [], chkBalance: String = "0", extra: [SFAccount] = [], errors: [String] = []) -> SFResponse {
        SFResponse(errors: errors, accounts: [SFAccount(id: "ACT-CHK", name: "Checking", balance: chkBalance, orgName: "Bank", transactions: chk),
                                              SFAccount(id: "ACT-VISA", name: "Visa", orgName: "Bank", transactions: visa)] + extra)
    }

    private func tx(_ id: String, _ dayOffset: Int, _ amount: String, _ description: String = "SHOP", pending: Bool = false) -> SFTransaction {
        SFTransaction(id: id, posted: day(dayOffset), amount: amount, description: description, pending: pending)
    }

    private func run(_ f: Fixture, _ r: SFResponse) throws -> SimpleFINReport {
        let (ops, report) = try f.c.planSimpleFINImport(r, timeZone: utc)
        if !ops.isEmpty { try f.c.perform(ops, author: .bank) }
        return report
    }

    @Test func newRowsAreUnapprovedBankRows() throws {
        let f = try setup()
        let report = try run(f, response(chk: [tx("1", 0, "-12.34", "TRADER JOES #4")]))
        let t = try #require(try f.c.transaction(id: "sf-ACT-CHK-1"))
        #expect(t.date == "2026-01-05" && t.amount == -12_340 && !t.approved && t.cleared == .cleared && t.author == .bank)
        #expect(t.bankImportID == "sf:ACT-CHK:1" && t.rawPayee == "TRADER JOES #4")
        #expect(report.newTransactions == 1 && report.fetchedAccounts == 2)
    }

    @Test func importingTheSameResponseTwiceChangesNothing() throws {
        let f = try setup()
        let r = response(chk: [tx("1", 0, "-12.34")], visa: [tx("2", 1, "-5")])
        _ = try run(f, r)
        let before = try f.c.changes(since: 0).count
        let again = try f.c.planSimpleFINImport(r, timeZone: utc)
        #expect(again.ops.isEmpty && again.report.newTransactions == 0 && again.report.matchedExisting == 0)
        #expect(try f.c.changes(since: 0).count == before)
    }

    @Test func aRowYNABAlreadyHasGetsTheBankIdInsteadOfADuplicate() throws {
        let f = try setup()
        try f.c.perform([.putTransaction(Transaction(id: "ynab-1", accountID: "chk", date: "2026-01-03", categoryID: "groc", amount: -12_340, approved: true, ynabID: "y1"))], author: .importer)
        let report = try run(f, response(chk: [tx("1", 0, "-12.34", "TRADER JOES")]))
        #expect(report.matchedExisting == 1 && report.newTransactions == 0)
        let t = try #require(try f.c.transaction(id: "ynab-1"))
        #expect(t.bankImportID == "sf:ACT-CHK:1" && t.categoryID == "groc" && t.approved && t.rawPayee == "TRADER JOES")
        #expect(try f.c.transactions().count == 1)
    }

    @Test func twoIdenticalSameDayChargesBothImport() throws {
        let f = try setup()
        let report = try run(f, response(chk: [tx("a", 0, "-4.00", "COFFEE"), tx("b", 0, "-4.00", "COFFEE")]))
        #expect(try report.newTransactions == 2 && (try f.c.transactions().count) == 2)
    }

    @Test func oneExistingRowMatchesOnlyOneOfTwoIdenticalCharges() throws {
        let f = try setup()
        try f.c.perform([.putTransaction(Transaction(id: "m", accountID: "chk", date: "2026-01-05", amount: -4_000))], author: .mac)
        let report = try run(f, response(chk: [tx("a", 0, "-4.00"), tx("b", 0, "-4.00")]))
        #expect(try report.matchedExisting == 1 && report.newTransactions == 1 && (try f.c.transactions().count) == 2)
    }

    @Test func pendingAndUnreadableAreSkippedAndCounted() throws {
        let f = try setup()
        let report = try run(f, response(chk: [tx("p", 0, "-1", pending: true), tx("bad", 0, "lots"), tx("ok", 0, "-2")]))
        #expect(report.skippedPending == 1 && report.skippedUnreadable == 1 && report.newTransactions == 1)
    }

    @Test func unlinkedAccountIsReportedNotImported() throws {
        let f = try setup()
        let report = try run(f, response(extra: [SFAccount(id: "ACT-X", name: "Old Savings", orgName: "Bank", transactions: [tx("9", 0, "-1")])]))
        #expect(try report.unlinkedAccounts == ["Bank Old Savings"] && (try f.c.transactions().isEmpty))
    }

    @Test func cardPaymentLinksToItsCheckingSide() throws {
        let f = try setup()
        let report = try run(f, response(chk: [tx("c1", 0, "-250.00", "CHASE CARD PAYMENT")], visa: [tx("v1", 2, "250.00", "PAYMENT THANK YOU")]))
        #expect(report.linkedTransfers == 1)
        let out = try #require(try f.c.transaction(id: "sf-ACT-CHK-c1")), inn = try #require(try f.c.transaction(id: "sf-ACT-VISA-v1"))
        #expect(out.transferPairID == inn.id && inn.transferPairID == out.id && out.categoryID == nil && inn.categoryID == nil)
    }

    @Test func aLaterCheckingRowLinksToAnEarlierCardRow() throws {
        let f = try setup()
        _ = try run(f, response(visa: [tx("v1", 0, "100.00", "PAYMENT")]))
        let report = try run(f, response(chk: [tx("c1", 1, "-100.00", "CARD PAYMENT")], visa: [tx("v1", 0, "100.00", "PAYMENT")]))
        #expect(try report.linkedTransfers == 1 && (try f.c.transaction(id: "sf-ACT-VISA-v1")?.transferPairID) == "sf-ACT-CHK-c1")
    }

    @Test func aTieBetweenEquallyCloseCandidatesIsLeftAlone() throws {
        let f = try setup()
        try f.c.perform(Coinbox.createAccountOps(Account(id: "chk2", name: "Checking 2", simplefinID: "ACT-CHK2")), author: .mac)
        let two = SFAccount(id: "ACT-CHK2", name: "Checking 2", transactions: [tx("c2", 0, "-75.00")])
        let report = try run(f, response(chk: [tx("c1", 0, "-75.00")], visa: [tx("v1", 0, "75.00")], extra: [two]))
        #expect(report.linkedTransfers == 0 && report.ambiguousTransfers.count == 1)
        #expect(try f.c.transaction(id: "sf-ACT-VISA-v1")?.transferPairID == nil)
    }

    @Test func differentAmountsNeverLink() throws {
        let f = try setup()
        let report = try run(f, response(chk: [tx("c1", 0, "-250.00")], visa: [tx("v1", 0, "249.99")]))
        #expect(report.linkedTransfers == 0)
    }

    @Test func bridgeMessagesAreReportedAndEmptyResponseIsFine() throws {
        let f = try setup()
        let report = try run(f, SFResponse(errors: ["Connection to https://bob:pw@bank.example needs attention"], accounts: []))
        #expect(report.bridgeMessages == ["Connection to https://bank.example needs attention"] && report.fetchedAccounts == 0)
    }

    @Test func balancesAreReportedAgainstCoinbox() throws {
        let f = try setup()
        let report = try run(f, response(chk: [tx("1", 0, "-10")], chkBalance: "90.00"))
        #expect(report.balances.first { $0.account == "Checking" } == .init(account: "Checking", simplefin: 90_000, coinbox: -10_000))
    }

    @Test func timeZoneDecidesTheLocalDate() throws {
        let f = try setup()
        let late = SFTransaction(id: "z", posted: 1_767_582_000, amount: "-1", description: "X")      // 2026-01-05 03:00 UTC = Jan 4 evening in New York
        _ = try f.c.planSimpleFINImport(response(chk: [late]), timeZone: utc)
        let newYork = try f.c.planSimpleFINImport(response(chk: [late]), timeZone: TimeZone(identifier: "America/New_York")!)
        guard case let .putTransaction(t) = newYork.ops[0] else { Issue.record("no op"); return }
        #expect(t.date == "2026-01-04")
    }

    // The whole sync, with a rule

    private struct Canned: SimpleFINFetcher {
        let data: Data
        func fetch(since: Date) async throws -> Data { data }
    }

    @Test func syncImportsThenRulesCategorizeAndApprove() async throws {
        let f = try setup()
        try f.c.perform([.putRule(Rule(id: "r", name: "Groceries", payee: TextMatch(.contains, "trader"), actions: RuleActions(renamePayee: "Trader Joe's", categoryID: "groc", approve: true)))], author: .claude)
        let data = try JSONEncoder().encode(response(chk: [tx("1", 0, "-12.34", "TRADER JOES #4"), tx("2", 0, "-9.00", "MYSTERY")]))
        let report = try await f.c.runSimpleFINSync(fetcher: Canned(data: data), timeZone: utc)
        #expect(report.newTransactions == 2 && report.rulesApplied == 1)
        #expect(try f.c.transaction(id: "sf-ACT-CHK-1")?.approved == true && (try f.c.transaction(id: "sf-ACT-CHK-1")?.categoryID) == "groc")
        #expect(try f.c.transaction(id: "sf-ACT-CHK-2")?.approved == false)
        #expect(try f.c.changes(since: 0, author: .bank).count >= 2)
    }

    @Test func syncRejectsAnUnreadableAnswer() async throws {
        let f = try setup()
        await #expect(throws: CoinboxError.self) { _ = try await f.c.runSimpleFINSync(fetcher: Canned(data: Data("<html>".utf8))) }
    }
}
