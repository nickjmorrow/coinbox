#if os(macOS)
import CoinboxCore
import SwiftUI

struct PayoffView: View {
    @Environment(AppModel.self) private var model
    @State private var budget = ""
    @State private var strategy: PayoffStrategy = .avalanche

    private var cards: [Account] { model.creditAccounts.filter { model.balance($0) < 0 } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Card Payoff").font(.title2.weight(.semibold))
                    Text("Enter each card's APR and minimum, say how much a month goes to cards, and see when you're done and what it costs.").font(.callout).foregroundStyle(Theme.dim)
                }
                if cards.isEmpty { Text("No credit card has a balance.").foregroundStyle(Theme.dim) }
                ForEach(cards, id: \.id) { TermsRow(account: $0) }
                if !cards.isEmpty {
                    Card {
                        HStack {
                            TextField("Dollars a month for all cards", text: $budget).frame(maxWidth: 240)
                            Picker("", selection: $strategy) { Text("Avalanche: highest APR first").tag(PayoffStrategy.avalanche); Text("Snowball: smallest balance first").tag(PayoffStrategy.snowball) }.labelsHidden().frame(width: 280)
                        }
                    }
                    if let b = Fmt.parse(budget), b > 0, let plan = model.payoff(strategy: strategy, monthlyBudget: b) { result(plan) }
                }
            }.padding(20)
        }.background(Theme.background)
    }

    @ViewBuilder private func result(_ plan: PayoffPlan) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(plan.warnings, id: \.self) { Text($0).font(.callout).foregroundStyle(Theme.gold) }
                if let free = plan.debtFreeMonth, let n = plan.months {
                    Text("Debt-free in \(MonthKey(free)?.title ?? free) (\(n) months)").font(.title3.weight(.semibold)).foregroundStyle(Theme.done)
                    HStack(spacing: 24) {
                        stat("Interest", Money.format(plan.totalInterest))
                        if let saved = plan.interestSaved { stat("Saved vs minimums only", Money.format(saved)) }
                    }
                }
                ForEach(plan.cards, id: \.name) { c in
                    HStack { Text(c.name); Spacer(); Text(c.paidOffIn.flatMap { MonthKey($0)?.title } ?? "not paid off").foregroundStyle(Theme.dim); Text(Money.format(c.interest)).monospacedDigit().frame(width: 100, alignment: .trailing) }
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(Theme.dim); Text(value).font(.headline).monospacedDigit() }
    }
}

private struct TermsRow: View {
    @Environment(AppModel.self) private var model
    let account: Account
    @State private var apr = ""
    @State private var minimum = ""

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) { Text(account.name).font(.headline); Text("owes \(Money.format(-model.balance(account)))").font(.callout).foregroundStyle(Theme.dim) }
                Spacer()
                TextField("APR %", text: $apr).frame(width: 90).multilineTextAlignment(.trailing).onSubmit(save)
                TextField("Minimum $", text: $minimum).frame(width: 110).multilineTextAlignment(.trailing).onSubmit(save)
                Button("Save", action: save).disabled(Decimal(string: apr) == nil || Fmt.parse(minimum) == nil)
            }
        }.onAppear {
            if let t = model.cardTerms[account.id] { apr = String(format: "%.2f", Double(t.aprBasisPoints) / 100); minimum = Fmt.edit(t.minimumPayment) }
        }
    }

    private func save() {
        guard let rate = Decimal(string: apr), let min = Fmt.parse(minimum) else { return }
        model.setTerms(accountID: account.id, aprPercent: rate, minimum: min)
    }
}
#endif
