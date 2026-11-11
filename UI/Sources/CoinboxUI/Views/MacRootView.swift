#if os(macOS)
import CoinboxCore
import SwiftUI

/// The Mac app: a sidebar with the plan, the registers (all, and one per account), rules, payees and sync.
public struct MacRootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("macDestination") private var stored = "plan"
    @State private var addingAccount = false

    public init() {}

    enum Destination: Hashable {
        case plan, review, all, account(String), payoff, rules, payees, settings
        var key: String {
            switch self {
            case .plan: return "plan"
            case .review: return "review"
            case .all: return "all"
            case let .account(id): return "account:" + id
            case .payoff: return "payoff"
            case .rules: return "rules"
            case .payees: return "payees"
            case .settings: return "settings"
            }
        }
        init(key: String) {
            switch key {
            case "all": self = .all
            case "review": self = .review
            case "payoff": self = .payoff
            case "rules": self = .rules
            case "payees": self = .payees
            case "settings": self = .settings
            case let k where k.hasPrefix("account:"): self = .account(String(k.dropFirst(8)))
            default: self = .plan
            }
        }
    }

    private var selection: Binding<Destination?> {
        Binding(get: { Destination(key: stored) }, set: { if let d = $0 { stored = d.key } })
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Label("Plan", systemImage: "chart.pie").tag(Destination.plan)
                Label("Review", systemImage: "chart.bar.xaxis").tag(Destination.review)
                Label { HStack { Text("All Transactions"); Spacer(); if model.unapprovedCount > 0 { Pill(text: "\(model.unapprovedCount)", fill: Theme.accent) } } } icon: { Image(systemName: "list.bullet") }.tag(Destination.all)
                accountSection("Cash", model.cashAccounts)
                accountSection("Credit", model.creditAccounts)
                accountSection("Tracking", model.trackingAccounts)
                Section("Tools") {
                    Label("Card Payoff", systemImage: "creditcard").tag(Destination.payoff)
                    Label("Rules", systemImage: "wand.and.stars").tag(Destination.rules)
                    Label("Payees", systemImage: "person.text.rectangle").tag(Destination.payees)
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath").tag(Destination.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .scrollContentBackground(.hidden)
            .background(Theme.bar.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button { addingAccount = true } label: { Label("Add Account", systemImage: "plus") }.buttonStyle(.plain).foregroundStyle(Theme.accent).padding(10)
            }
        } detail: {
            switch Destination(key: stored) {
            case .plan: PlanView()
            case .review: ReviewView()
            case .all: RegisterView(accountID: nil)
            case let .account(id): RegisterView(accountID: id).id(id)
            case .payoff: PayoffView()
            case .rules: RulesView()
            case .payees: PayeesView()
            case .settings: SettingsView()
            }
        }
        .coinboxTheme()
        .frame(minWidth: 1000, minHeight: 640)
        .sheet(isPresented: $addingAccount) { AddAccountSheet() }
        .alert("Something didn't work", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: { Text(model.lastError ?? "") }
        .toolbar {
            ToolbarItemGroup {
                Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(!model.canUndo).keyboardShortcut("z", modifiers: .command)
                Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }.disabled(!model.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
    }

    @ViewBuilder private func accountSection(_ title: String, _ accounts: [Account]) -> some View {
        if !accounts.isEmpty {
            Section(title) {
                ForEach(accounts, id: \.id) { a in
                    HStack { Text(a.name); Spacer(); Text(Money.format(model.balance(a))).monospacedDigit().foregroundStyle(model.balance(a) < 0 ? Theme.danger : Theme.dim) }.tag(Destination.account(a.id))
                }
            }
        }
    }
}

struct AddAccountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: AccountKind = .checking
    @State private var balance = ""
    @State private var date = Date()

    var body: some View {
        Form {
            TextField("Name", text: $name)
            Picker("Type", selection: $kind) {
                ForEach(AccountKind.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            TextField("Balance", text: $balance, prompt: Text("0.00"))
            DatePicker("As of", selection: $date, displayedComponents: .date)
            Text([.mortgage, .loan, .asset].contains(kind) ? "Tracking accounts stay out of the plan." : kind == .creditCard ? "Enter what you owe as a negative amount. A payment category is created for the card." : "The balance becomes money to assign.")
                .font(.footnote).foregroundStyle(Theme.dim)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    model.addAccount(name: name.trimmingCharacters(in: .whitespaces), kind: kind, onBudget: ![.mortgage, .loan, .asset].contains(kind), startingBalance: Fmt.parse(balance) ?? 0, date: Fmt.iso(date))
                    dismiss()
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (!balance.isEmpty && Fmt.parse(balance) == nil)).keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped).frame(width: 420).padding()
    }
}

extension AccountKind {
    var label: String {
        switch self {
        case .checking: return "Checking"
        case .savings: return "Savings"
        case .cash: return "Cash"
        case .creditCard: return "Credit card"
        case .mortgage: return "Mortgage (tracking)"
        case .loan: return "Loan (tracking)"
        case .asset: return "Asset (tracking)"
        }
    }
}
#endif
