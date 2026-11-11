import Foundation
@testable import CoinboxCore

/// A small YNAB plan, shaped like the API's answers. Ids are short so tests can name them.
enum YNABFixture {
    static func snapshot() -> YNABSnapshot {
        let accounts = [
            YNABAccount(id: "a-chk", name: "Checking", type: "checking", balance: 1_990_000),
            YNABAccount(id: "a-visa", name: "Visa", type: "creditCard", balance: -530_000),
            YNABAccount(id: "a-sav", name: "Savings", type: "savings", balance: 1_500_000),
            YNABAccount(id: "a-mort", name: "Mortgage", type: "mortgage", onBudget: false, balance: -199_700_000),
        ]
        let groups = [
            YNABGroup(id: "g-int", name: "Internal Master Category", categories: [
                YNABCategory(id: "c-rta", categoryGroupId: "g-int", name: "Inflow: Ready to Assign"),
                YNABCategory(id: "c-unc", categoryGroupId: "g-int", name: "Uncategorized")]),
            YNABGroup(id: "g-ccp", name: "Credit Card Payments", categories: [YNABCategory(id: "c-ccp", categoryGroupId: "g-ccp", name: "Visa")]),
            YNABGroup(id: "g-bills", name: "Bills", categories: [
                YNABCategory(id: "c-rent", categoryGroupId: "g-bills", name: "Rent", goalType: "MF", goalDay: 1, goalTarget: 1_300_000),
                YNABCategory(id: "c-int", categoryGroupId: "g-bills", name: "Interest & Fees"),
                YNABCategory(id: "c-phone", categoryGroupId: "g-bills", name: "Phone", goalType: "NEED", goalDay: 5, goalCadence: 1, goalCadenceFrequency: 1, goalTarget: 60_000),
                YNABCategory(id: "c-ins", categoryGroupId: "g-bills", name: "Insurance", goalType: "NEED", goalCadence: 13, goalCadenceFrequency: 1, goalTarget: 1_200_000, goalTargetDate: "2026-12-15"),
                YNABCategory(id: "c-gone", categoryGroupId: "g-bills", name: "Old", deleted: true)]),
            YNABGroup(id: "g-fun", name: "Fun", hidden: true, categories: [
                YNABCategory(id: "c-fun", categoryGroupId: "g-fun", name: "Fun"),
                YNABCategory(id: "c-car", categoryGroupId: "g-fun", name: "Car wash", goalType: "NEED", goalDay: 0, goalCadence: 2, goalCadenceFrequency: 1, goalTarget: 25_000),
                YNABCategory(id: "c-trip", categoryGroupId: "g-fun", name: "Trip", goalType: "TBD", goalTarget: 600_000, goalTargetDate: "2026-06-30"),
                YNABCategory(id: "c-tb", categoryGroupId: "g-fun", name: "Cushion", goalType: "TB", goalTarget: 50_000)]),
        ]
        let payees = [YNABPayee(id: "p-emp", name: "Employer"), YNABPayee(id: "p-tr", name: "Transfer : Savings", transferAccountId: "a-sav"), YNABPayee(id: "p-old", name: "Gone", deleted: true)]
        let jan = YNABMonth(month: "2026-01-01", note: "tight", toBeBudgeted: 3_410_000, categories: [
            YNABMonthCategory(id: "c-rent", budgeted: 1_300_000, activity: -1_330_000, balance: -30_000),
            YNABMonthCategory(id: "c-fun", budgeted: 100_000, activity: -140_000, balance: 150_000),
            YNABMonthCategory(id: "c-ccp", budgeted: 0, activity: 0, balance: 0),
            YNABMonthCategory(id: "c-int", budgeted: 0, activity: -20_000, balance: -20_000),
        ])
        let tx: [YNABTransaction] = [
            YNABTransaction(id: "t1", date: "2026-01-02", amount: 3_000_000, accountId: "a-chk", payeeId: "p-emp", categoryId: "c-rta"),
            YNABTransaction(id: "t2", date: "2026-01-03", amount: -1_000_000, accountId: "a-chk", categoryId: "c-rent"),
            YNABTransaction(id: "t3", date: "2026-01-05", amount: -120_000, accountId: "a-visa", categoryId: "c-fun"),
            YNABTransaction(id: "t4", date: "2026-01-06", amount: -500_000, accountId: "a-chk", payeeId: "p-tr", transferAccountId: "a-sav", transferTransactionId: "t5"),
            YNABTransaction(id: "t5", date: "2026-01-06", amount: 500_000, accountId: "a-sav", transferAccountId: "a-chk", transferTransactionId: "t4"),
            YNABTransaction(id: "t6", date: "2026-01-20", amount: -120_000, accountId: "a-chk", transferAccountId: "a-visa", transferTransactionId: "t7"),
            YNABTransaction(id: "t7", date: "2026-01-20", amount: 120_000, accountId: "a-visa", transferAccountId: "a-chk", transferTransactionId: "t6"),
            YNABTransaction(id: "t8", date: "2026-01-21", amount: -300_000, accountId: "a-chk", categoryId: "c-rent", transferAccountId: "a-mort", transferTransactionId: "t9"),
            YNABTransaction(id: "t9", date: "2026-01-21", amount: 300_000, accountId: "a-mort", transferAccountId: "a-chk", transferTransactionId: "t8"),
            YNABTransaction(id: "t10", date: "2026-01-22", amount: -9_999, accountId: "a-chk", categoryId: "c-rent", deleted: true),
            YNABTransaction(id: "t11", date: "2026-01-31", amount: -10_000, accountId: "a-visa", categoryId: "c-rta"),
            YNABTransaction(id: "t12", date: "2026-01-08", amount: -50_000, accountId: "a-chk", subtransactions: [
                YNABSubtransaction(id: "s1", amount: -30_000, categoryId: "c-rent"), YNABSubtransaction(id: "s2", amount: -20_000, categoryId: "c-fun")]),
            YNABTransaction(id: "t13", date: "2026-01-31", amount: -20_000, accountId: "a-visa", categoryId: "c-int"),
            YNABTransaction(id: "t14", date: "2026-01-09", amount: -40_000, accountId: "a-chk", subtransactions: [
                YNABSubtransaction(id: "s3", amount: -30_000, categoryId: "c-rent"), YNABSubtransaction(id: "s4", amount: -10_000, categoryId: "c-unc")]),
        ]
        return YNABSnapshot(accounts: accounts, payees: payees, groups: groups, months: [jan], transactions: tx)
    }
}
