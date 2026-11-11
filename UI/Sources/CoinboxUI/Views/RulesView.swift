#if os(macOS)
import CoinboxCore
import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Rule?
    @State private var adding = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rules").font(.title2.weight(.semibold))
                    Text("The first rule that matches a transaction wins, so keep specific rules above general ones.").font(.callout).foregroundStyle(Theme.dim)
                }
                Spacer()
                Button("Apply to \(model.unapprovedCount) unapproved") { model.applyRules() }.buttonStyle(.bordered).disabled(model.unapprovedCount == 0)
                Button { adding = true } label: { Label("Add rule", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }.padding(16).background(Theme.bar)
            if model.rules.isEmpty {
                Text("No rules yet.").foregroundStyle(Theme.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.rules, id: \.id) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) { Text(r.name).font(.headline); Text(summary(r)).font(.callout).foregroundStyle(Theme.dim).lineLimit(2) }
                            Spacer()
                            if RuleEngine.isBrokenRegex(r.payee) || RuleEngine.isBrokenRegex(r.memo) { Pill(text: "bad regex", fill: Theme.danger) }
                            Button("Edit") { editing = r }.buttonStyle(.borderless)
                        }.padding(.vertical, 3).contentShape(Rectangle()).onTapGesture(count: 2) { editing = r }
                    }.onMove { from, to in var list = model.rules; list.move(fromOffsets: from, toOffset: to); model.reorder(list) }
                }.themedList()
            }
        }
        .background(Theme.background)
        .sheet(item: $editing) { RuleEditor(rule: $0, isNew: false) }
        .sheet(isPresented: $adding) { RuleEditor(rule: Rule(order: model.rules.count, name: "", actions: RuleActions()), isNew: true) }
    }

    private func summary(_ r: Rule) -> String {
        var when: [String] = []
        if let p = r.payee { when.append("payee \(p.mode.rawValue) “\(p.text)”") }
        if let a = r.amount {
            switch a {
            case let .equals(v): when.append("amount is \(Money.format(v))")
            case let .range(lo, hi): when.append("amount \(Money.format(lo)) to \(Money.format(hi))")
            case let .endsWithCents(c): when.append("amount ends in .\(String(format: "%02d", c))")
            }
        }
        if let m = r.memo { when.append("memo \(m.mode.rawValue) “\(m.text)”") }
        if !r.accountIDs.isEmpty { when.append("in " + r.accountIDs.map { model.accountName($0) }.joined(separator: ", ")) }
        var then: [String] = []
        if let n = r.actions.renamePayee { then.append("rename to “\(n)”") }
        if let c = r.actions.categoryID { then.append("category \(model.categoryName(c))") }
        if let m = r.actions.memo { then.append("memo “\(m)”") }
        if r.actions.approve { then.append("approve") }
        return "When " + (when.isEmpty ? "anything" : when.joined(separator: " and ")) + " → " + (then.isEmpty ? "nothing" : then.joined(separator: ", "))
    }
}

extension Rule: @retroactive Identifiable {}

struct RuleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var rule: Rule
    let isNew: Bool
    @State private var payeeMode = "any"
    @State private var payeeText = ""
    @State private var amountKind = "any"
    @State private var amountA = ""
    @State private var amountB = ""
    @State private var memoText = ""
    @State private var accountID: String?

    init(rule: Rule, isNew: Bool) { _rule = State(initialValue: rule); self.isNew = isNew }

    var body: some View {
        Form {
            TextField("Name", text: $rule.name)
            Section("When") {
                Picker("Bank payee", selection: $payeeMode) { Text("Any").tag("any"); Text("contains").tag("contains"); Text("equals").tag("equals"); Text("matches regex").tag("regex") }
                if payeeMode != "any" { TextField("Text", text: $payeeText) }
                Picker("Amount", selection: $amountKind) { Text("Any").tag("any"); Text("equals").tag("equals"); Text("between").tag("range"); Text("ends in cents").tag("cents") }
                if amountKind == "equals" || amountKind == "cents" { TextField(amountKind == "cents" ? "Cents, 0–99" : "Amount (negative for outflows)", text: $amountA) }
                if amountKind == "range" { TextField("From", text: $amountA); TextField("To", text: $amountB) }
                TextField("Memo contains", text: $memoText)
                Picker("Account", selection: $accountID) { Text("Any").tag(String?.none); ForEach(model.openAccounts, id: \.id) { Text($0.name).tag(String?.some($0.id)) } }
            }
            Section("Then") {
                TextField("Rename payee to", text: Binding(get: { rule.actions.renamePayee ?? "" }, set: { rule.actions.renamePayee = $0.isEmpty ? nil : $0 }))
                CategoryPicker(title: "Category", selection: $rule.actions.categoryID)
                TextField("Set memo", text: Binding(get: { rule.actions.memo ?? "" }, set: { rule.actions.memo = $0.isEmpty ? nil : $0 }))
                Toggle("Approve", isOn: $rule.actions.approve)
            }
            HStack {
                if !isNew { Button("Delete", role: .destructive) { model.deleteRule(rule.id); dismiss() } }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save(); dismiss() }.disabled(rule.name.trimmingCharacters(in: .whitespaces).isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped).frame(width: 500).padding()
        .onAppear { load() }
    }

    private func load() {
        if let p = rule.payee { payeeMode = p.mode.rawValue; payeeText = p.text }
        switch rule.amount {
        case let .equals(v): amountKind = "equals"; amountA = Fmt.edit(v)
        case let .range(lo, hi): amountKind = "range"; amountA = Fmt.edit(lo); amountB = Fmt.edit(hi)
        case let .endsWithCents(c): amountKind = "cents"; amountA = String(c)
        case nil: break
        }
        memoText = rule.memo?.text ?? ""
        accountID = rule.accountIDs.first
    }

    private func save() {
        rule.payee = payeeMode == "any" || payeeText.isEmpty ? nil : TextMatch(TextMode(rawValue: payeeMode) ?? .contains, payeeText)
        switch amountKind {
        case "equals": rule.amount = Fmt.parse(amountA).map { .equals($0) }
        case "range": if let a = Fmt.parse(amountA), let b = Fmt.parse(amountB) { rule.amount = .range(min: Swift.min(a, b), max: Swift.max(a, b)) }
        case "cents": rule.amount = Int(amountA).map { .endsWithCents(Swift.max(0, Swift.min(99, $0))) }
        default: rule.amount = nil
        }
        rule.memo = memoText.isEmpty ? nil : TextMatch(.contains, memoText)
        rule.accountIDs = accountID.map { [$0] } ?? []
        model.save(rule)
    }
}

struct PayeesView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Payees").font(.title2.weight(.semibold))
                    Text("A default category fills in new transactions. It changes by itself when two of the last three agree, unless you lock it.").font(.callout).foregroundStyle(Theme.dim)
                }
                Spacer()
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
            }.padding(16).background(Theme.bar)
            List(model.payees.filter { $0.transferAccountID == nil && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }, id: \.id) { p in
                PayeeRow(payee: p)
            }.themedList()
        }.background(Theme.background)
    }
}

struct PayeeRow: View {
    @Environment(AppModel.self) private var model
    let payee: Payee
    var body: some View {
        HStack {
            Text(payee.name).frame(maxWidth: .infinity, alignment: .leading)
            CategoryPicker(title: "", selection: Binding(get: { payee.defaultCategoryID }, set: { var p = payee; p.defaultCategoryID = $0; model.save(p) })).labelsHidden().frame(width: 220)
            Toggle("Lock", isOn: Binding(get: { payee.defaultLocked }, set: { var p = payee; p.defaultLocked = $0; model.save(p) })).toggleStyle(.checkbox).help("A locked default never changes by itself.")
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var url = ""
    @State private var token = ""

    var body: some View {
        Form {
            Section("Sync hub") {
                Text(model.syncStatus).foregroundStyle(Theme.dim)
                TextField("Hub address", text: $url, prompt: Text("http://100.x.y.z:8791"))
                SecureField("Token", text: $token)
                HStack {
                    Button("Save") { if model.configureSync(url: url, token: token) { token = ""; model.startAutoSync() } }.disabled(url.isEmpty || token.isEmpty)
                    Button(model.syncing ? "Syncing…" : "Sync now") { Task { await model.syncNow() } }.disabled(model.syncing || !model.syncConfigured)
                    Button(model.refreshingBank ? "Asking the bank…" : "Refresh bank") { Task { await model.refreshBank() } }.disabled(model.refreshingBank || !model.syncConfigured)
                }
                Text("The hub on your server keeps a full copy, pulls bank activity every six hours and shares changes between your devices.").font(.footnote).foregroundStyle(Theme.dim)
            }
            Section("Data") {
                LabeledContent("Accounts", value: "\(model.accounts.count)")
                LabeledContent("Categories", value: "\(model.categories.count)")
                LabeledContent("Rules", value: "\(model.rules.count)")
            }
        }.formStyle(.grouped).frame(maxWidth: 560).padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(Theme.background)
    }
}
#endif
