import Foundation

/// What a credit card charges: the annual rate (in basis points, 2499 = 24.99%) and the smallest payment the issuer asks for.
public struct CardTerms: Codable, Sendable, Equatable {
    public var accountID: String
    public var aprBasisPoints: Int
    public var minimumPayment: Milliunits

    public init(accountID: String, aprBasisPoints: Int, minimumPayment: Milliunits) { self.accountID = accountID; self.aprBasisPoints = aprBasisPoints; self.minimumPayment = minimumPayment }
}

public struct AmazonItem: Codable, Sendable, Equatable {
    public var name: String
    /// Before tax; positive.
    public var amount: Milliunits
    public var categoryID: String

    public init(name: String, amount: Milliunits, categoryID: String) { self.name = name; self.amount = amount; self.categoryID = categoryID }
}

/// An Amazon charge Claude split by what was in the order (Amazon has no API; Claude reads the order history).
public struct AmazonLink: Codable, Sendable, Equatable {
    public var transactionID: String
    public var orderID: String
    public var items: [AmazonItem]
    public var tax: Milliunits

    public init(transactionID: String, orderID: String, items: [AmazonItem], tax: Milliunits) { self.transactionID = transactionID; self.orderID = orderID; self.items = items; self.tax = tax }
}

public enum PayoffStrategy: String, Codable, Sendable { case avalanche, snowball }

public struct PayoffCard: Sendable, Equatable {
    public var id: String
    public var name: String
    public var owed: Milliunits
    public var aprBasisPoints: Int
    public var minimumPayment: Milliunits

    public init(id: String, name: String, owed: Milliunits, aprBasisPoints: Int, minimumPayment: Milliunits) { self.id = id; self.name = name; self.owed = owed; self.aprBasisPoints = aprBasisPoints; self.minimumPayment = minimumPayment }
}

public struct PayoffPlan: Codable, Sendable, Equatable {
    public struct CardResult: Codable, Sendable, Equatable { public var name: String; public var paidOffIn: String?; public var interest: Milliunits }
    public struct Month: Codable, Sendable, Equatable { public var month: String; public var payments: [String: Milliunits]; public var remaining: Milliunits }
    public var strategy: PayoffStrategy
    public var monthlyBudget: Milliunits
    public var debtFreeMonth: String?
    public var months: Int?
    public var totalInterest: Milliunits
    /// Interest the same cards would cost paying only their minimums.
    public var minimumOnlyInterest: Milliunits?
    public var interestSaved: Milliunits?
    public var cards: [CardResult]
    public var schedule: [Month]
    public var warnings: [String]
}

public enum PayoffPlanner {
    struct Run { var months: [PayoffPlan.Month] = []; var interest: [String: Milliunits] = [:]; var paidOff: [String: String] = [:]; var finished = false }

    static func interest(_ balance: Milliunits, apr: Int) -> Milliunits { Money.divideRounded(balance * Int64(apr), 120_000) }

    /// Simulates paying every card's minimum each month and putting the rest of `budget` on one card at a time. No new spending is assumed.
    static func simulate(_ cards: [PayoffCard], budget: Milliunits, strategy: PayoffStrategy, start: MonthKey, limit: Int = 600) -> Run {
        var balances = Dictionary(cards.map { ($0.id, $0.owed) }, uniquingKeysWith: { a, _ in a })
        var run = Run()
        var month = start
        for _ in 0..<limit {
            guard balances.values.contains(where: { $0 > 0 }) else { run.finished = true; break }
            for c in cards where balances[c.id]! > 0 {
                let i = interest(balances[c.id]!, apr: c.aprBasisPoints)
                balances[c.id]! += i
                run.interest[c.id, default: 0] += i
            }
            var left = budget
            var paid: [String: Milliunits] = [:]
            for c in cards where balances[c.id]! > 0 {
                let p = min(balances[c.id]!, c.minimumPayment, max(0, left))
                paid[c.id] = p; balances[c.id]! -= p; left -= p
            }
            let order = cards.filter { balances[$0.id]! > 0 }.sorted {
                strategy == .avalanche ? ($0.aprBasisPoints, balances[$1.id]!, $1.id) > ($1.aprBasisPoints, balances[$0.id]!, $0.id) : (balances[$0.id]!, $0.id) < (balances[$1.id]!, $1.id)
            }
            for c in order where left > 0 {
                let p = min(balances[c.id]!, left)
                paid[c.id, default: 0] += p; balances[c.id]! -= p; left -= p
            }
            for c in cards where balances[c.id]! == 0 && run.paidOff[c.id] == nil && c.owed > 0 { run.paidOff[c.id] = month.string }
            run.months.append(.init(month: month.string, payments: paid, remaining: balances.values.reduce(0, +)))
            month = month.next
        }
        if !run.finished { run.finished = !balances.values.contains { $0 > 0 } }
        return run
    }

    public static func plan(cards all: [PayoffCard], monthlyBudget: Milliunits, strategy: PayoffStrategy, start: MonthKey) -> PayoffPlan {
        let cards = all.filter { $0.owed > 0 }
        var warnings: [String] = []
        let minimums = cards.reduce(0) { $0 + $1.minimumPayment }
        if monthlyBudget < minimums { warnings.append("The budget \(Money.format(monthlyBudget)) is less than the minimums \(Money.format(minimums)) a month.") }
        for c in cards where c.minimumPayment <= interest(c.owed, apr: c.aprBasisPoints) { warnings.append("\(c.name): the minimum payment doesn't cover a month's interest, so on its own it never pays off.") }
        let run = simulate(cards, budget: monthlyBudget, strategy: strategy, start: start)
        let baseline = simulate(cards, budget: minimums, strategy: strategy, start: start)
        let total = run.interest.values.reduce(0, +)
        if !run.finished { warnings.append("Not paid off within 50 years at this budget.") }
        let baselineTotal = baseline.interest.values.reduce(0, +)
        return PayoffPlan(strategy: strategy, monthlyBudget: monthlyBudget, debtFreeMonth: run.finished ? run.months.last?.month : nil, months: run.finished ? run.months.count : nil,
                          totalInterest: total, minimumOnlyInterest: baseline.finished ? baselineTotal : nil,
                          interestSaved: baseline.finished && run.finished ? baselineTotal - total : nil,
                          cards: cards.map { .init(name: $0.name, paidOffIn: run.paidOff[$0.id], interest: run.interest[$0.id] ?? 0) },
                          schedule: Array(run.months.prefix(36)), warnings: warnings)
    }
}

extension Coinbox {
    /// The payoff plan for every open on-budget credit card that has a balance, using the terms entered for each.
    public func payoffPlan(strategy: PayoffStrategy, monthlyBudget: Milliunits, start: MonthKey) throws -> PayoffPlan {
        let terms = Dictionary(try cardTerms().map { ($0.accountID, $0) }, uniquingKeysWith: { a, _ in a })
        let balances = try accountBalances()
        var cards: [PayoffCard] = []
        var missing: [String] = []
        for a in try accounts() where a.kind == .creditCard && a.onBudget && !a.closed {
            let owed = -(balances[a.id]?.total ?? 0)
            guard owed > 0 else { continue }
            guard let t = terms[a.id] else { missing.append(a.name); continue }
            cards.append(PayoffCard(id: a.id, name: a.name, owed: owed, aprBasisPoints: t.aprBasisPoints, minimumPayment: t.minimumPayment))
        }
        var plan = PayoffPlanner.plan(cards: cards, monthlyBudget: monthlyBudget, strategy: strategy, start: start)
        for name in missing { plan.warnings.append("\(name) has a balance but no APR or minimum payment yet (`card-terms put`); it isn't in this plan.") }
        return plan
    }

    /// Ops that split an Amazon charge into its items, with the tax prorated across them (largest remainder, so the lines add up exactly), and record the order.
    public func amazonSplitOps(transactionID: String, orderID: String, items: [AmazonItem], tax: Milliunits?) throws -> [Op] {
        guard var t = try transaction(id: transactionID) else { throw CoinboxError.notFound("transaction \(transactionID)") }
        guard !items.isEmpty, items.allSatisfy({ $0.amount > 0 }) else { throw CoinboxError.invalid("give at least one item, each with a positive pre-tax amount") }
        let sign: Milliunits = t.amount < 0 ? -1 : 1
        let subtotal = items.reduce(0) { $0 + $1.amount }
        let taxTotal = tax ?? (abs(t.amount) - subtotal)
        guard taxTotal >= 0, subtotal + taxTotal == abs(t.amount) else {
            throw CoinboxError.invalid("the items (\(Money.format(subtotal))) plus tax (\(Money.format(taxTotal))) don't add up to the charge of \(Money.format(abs(t.amount)))")
        }
        var shares = items.map { taxTotal * $0.amount / subtotal }
        var remainder = taxTotal - shares.reduce(0, +)
        let byFraction = items.indices.sorted { (taxTotal * items[$0].amount % subtotal, -$0) > (taxTotal * items[$1].amount % subtotal, -$1) }
        for i in byFraction where remainder > 0 { shares[i] += 1; remainder -= 1 }
        if items.count == 1 {      // one item needs no split: the whole charge goes to its category
            t.categoryID = items[0].categoryID
            t.splits = []
        } else {
            t.categoryID = nil
            t.splits = items.indices.map { SplitLine(categoryID: items[$0].categoryID, amount: sign * (items[$0].amount + shares[$0]), memo: items[$0].name) }
        }
        return [.putTransaction(t), .putAmazonLink(AmazonLink(transactionID: transactionID, orderID: orderID, items: items, tax: taxTotal))]
    }
}
