import ArgumentParser
import CoinboxCore
import Foundation

struct PayoffStrategyArg: ExpressibleByArgument {
    let value: PayoffStrategy
    init?(argument: String) { guard let s = PayoffStrategy(rawValue: argument) else { return nil }; value = s }
    var defaultValueDescription: String { value.rawValue }
}

struct CardTermsGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "card-terms", abstract: "Each credit card's APR and minimum payment, for the payoff planner.", subcommands: [List.self, Put.self, Delete.self])

    struct List: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        func run() throws { try Output.json(try global.open().cardTerms()) }
    }
    struct Put: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set a card's APR (percent, like 24.99) and minimum payment (dollars).")
        @OptionGroup var global: GlobalOptions
        @Option(help: "Credit card account id.") var account: String
        @Option(help: "APR in percent, like 24.99.") var apr: String
        @Option(help: "Minimum monthly payment in dollars.") var minimum: String
        func run() throws {
            guard let rate = Decimal(string: apr), rate >= 0, rate < 100 else { throw CoinboxError.invalid("the APR should be a percentage like 24.99") }
            let basis = Int(truncating: NSDecimalNumber(decimal: rate * 100).rounding(accordingToBehavior: nil))
            let terms = CardTerms(accountID: account, aprBasisPoints: basis, minimumPayment: try parseDollars(minimum))
            try global.open().perform([.putCardTerms(terms)], author: global.author)
            try Output.json(terms)
        }
    }
    struct Delete: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var account: String
        func run() throws { try global.open().perform([.deleteCardTerms(accountID: account)], author: global.author); try Output.json(["deleted": account]) }
    }
}

struct PayoffCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "payoff", abstract: "A card payoff plan: avalanche (highest APR first) or snowball (smallest balance first), payoff dates and interest saved.")
    @OptionGroup var global: GlobalOptions
    @Option(help: "Dollars a month for all cards together.") var budget: String
    @Option(help: "avalanche or snowball.") var strategy = PayoffStrategyArg(argument: "avalanche")!
    @Option(help: "First month to pay in (default: this month).") var month: String?
    func run() throws {
        let start = try month.map { MonthKey(try validMonth($0))! } ?? MonthKey.containing(date: ISO8601DateFormatter().string(from: Date()).prefix(10).description)!
        try Output.json(try global.open().payoffPlan(strategy: strategy.value, monthlyBudget: try parseDollars(budget), start: start))
    }
}

struct AmazonSplitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "amazon-split", abstract: "Split an Amazon charge by the items in the order, prorating tax, and record the order.")
    @OptionGroup var global: GlobalOptions
    @Argument var transactionID: String
    @Option(help: "The Amazon order number.") var order: String
    @Option(help: "Items as JSON: [{\"name\":…, \"amount\":<milliunits before tax>, \"categoryID\":…}].") var items: String
    @Option(help: "Total tax in dollars; worked out from the charge when left out.") var tax: String?
    func run() throws {
        let c = try global.open()
        let list = try decodeJSON([AmazonItem].self, items)
        try c.perform(try c.amazonSplitOps(transactionID: transactionID, orderID: order, items: list, tax: try tax.map(parseDollars)), author: global.author)
        try Output.json(try c.transaction(id: transactionID))
    }
}

struct AmazonLinkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "amazon-link", abstract: "The recorded Amazon order for a transaction.")
    @OptionGroup var global: GlobalOptions
    @Argument var transactionID: String
    func run() throws {
        guard let l = try global.open().amazonLink(transactionID: transactionID) else { throw CoinboxError.notFound("amazon order for \(transactionID)") }
        try Output.json(l)
    }
}
