import Foundation
import GRDB

extension Coinbox {
    /// The ops that create an account. A credit card also gets its payment category.
    public static func createAccountOps(_ account: Account) -> [Op] {
        var ops: [Op] = [.putAccount(account)]
        if account.kind == .creditCard {
            ops.append(.putCategory(Category(id: "card-payment-\(account.id)", groupID: CategoryGroup.cardPaymentsID, name: account.name,
                                             kind: .cardPayment(accountID: account.id))))
        }
        return ops
    }

    /// Two linked transactions moving `amount` (> 0) from one account to another. Between two on-budget accounts there is no
    /// category; between an on-budget and a tracking account the on-budget leg needs one and counts as spending (or income).
    public func transferOps(id: String, date: String, from: String, to: String, amount: Milliunits, categoryID: String? = nil,
                            memo: String? = nil, author: Author) throws -> [Op] {
        guard amount > 0 else { throw CoinboxError.invalid("a transfer amount must be positive") }
        guard let source = try account(id: from) else { throw CoinboxError.notFound("account \(from)") }
        guard let target = try account(id: to) else { throw CoinboxError.notFound("account \(to)") }
        switch (source.onBudget, target.onBudget) {
        case (true, true): if categoryID != nil { throw CoinboxError.invalid("a transfer between on-budget accounts has no category") }
        case (false, false): throw CoinboxError.invalid("a transfer needs at least one on-budget account")
        default: if categoryID == nil { throw CoinboxError.invalid("a transfer to or from a tracking account needs a category") }
        }
        let outID = "\(id)-out", inID = "\(id)-in"
        return [
            .putTransaction(Transaction(id: outID, accountID: from, date: date, categoryID: source.onBudget ? categoryID : nil, memo: memo,
                                        amount: -amount, transferPairID: inID, author: author)),
            .putTransaction(Transaction(id: inID, accountID: to, date: date, categoryID: target.onBudget ? categoryID : nil, memo: memo,
                                        amount: amount, transferPairID: outID, author: author)),
        ]
    }
}
