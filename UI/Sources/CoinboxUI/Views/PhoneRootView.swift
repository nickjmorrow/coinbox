#if os(iOS)
import CoinboxCore
import SwiftUI

/// The iPhone app: check a category before spending, add a cash spend, approve imports, see balances.
public struct PhoneRootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0
    @State private var adding = false

    public init() {}

    public var body: some View {
        TabView(selection: $tab) {
            NavigationStack { PhonePlanView(add: { adding = true }) }.tabItem { Label("Plan", systemImage: "chart.pie") }.tag(0)
            NavigationStack { PhoneApproveView(add: { adding = true }) }.tabItem { Label("Approve", systemImage: "checkmark.circle") }.badge(model.unapprovedCount).tag(1)
            NavigationStack { PhoneAccountsView(add: { adding = true }) }.tabItem { Label("Accounts", systemImage: "building.columns") }.tag(2)
        }
        .sheet(isPresented: $adding) { AddTransactionView() }
        .coinboxTheme()
        .alert("Something didn't work", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: { Text(model.lastError ?? "") }
        .refreshable { await model.syncNow() }
    }
}

/// The nav-bar button that opens the add-transaction sheet.
struct AddButton: View {
    let action: () -> Void
    var body: some View { Button(action: action) { Image(systemName: "plus.circle.fill").font(.title2) }.accessibilityLabel("Add transaction") }
}

struct PhonePlanView: View {
    let add: () -> Void
    @Environment(AppModel.self) private var model
    @State private var moving: CoinboxCore.Category?

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready to Assign").font(.caption).foregroundStyle(Theme.dim)
                        Text(Money.format(model.summary.readyToAssign)).font(.system(.title, design: .rounded).weight(.bold)).foregroundStyle(model.summary.readyToAssign < 0 ? Theme.danger : Theme.done)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Runway").font(.caption).foregroundStyle(Theme.dim)
                        Text(model.runway.months.map { String(format: "%.1f mo", $0) } ?? "–").font(.title3.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                }.listRowBackground(Theme.card)
            }
            ForEach(model.planGroups, id: \.group.id) { entry in
                Section(entry.group.name) {
                    ForEach(entry.categories, id: \.id) { c in
                        let m = model.summary.categories[c.id] ?? CategoryMonth()
                        Button { if c.kind != .cardInterest { moving = c } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).foregroundStyle(Theme.text)
                                    if m.underfunded > 0 { Text("needs \(Money.format(m.underfunded))").font(.caption).foregroundStyle(Theme.gold) }
                                }
                                Spacer()
                                if c.kind != .cardInterest {
                                    Pill(text: Money.format(m.available), fill: m.cashOverspent > 0 ? Theme.danger : m.creditOverspent > 0 ? Theme.gold : m.available > 0 ? Theme.done : Theme.raised,
                                         foreground: m.available == 0 ? Theme.dim : Theme.background)
                                }
                            }
                        }.listRowBackground(Theme.card)
                    }
                }
            }
        }
        .themedList()
        .navigationTitle(model.month.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { model.month = model.month.previous } label: { Image(systemName: "chevron.left") } }
            ToolbarItemGroup(placement: .topBarTrailing) { Button { model.month = model.month.next } label: { Image(systemName: "chevron.right") }; AddButton(action: add) }
        }
        .sheet(item: $moving) { PhoneMoveMoneyView(from: $0) }
    }
}

struct PhoneMoveMoneyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let from: CoinboxCore.Category
    @State private var to: String?
    @State private var amount = ""

    var body: some View {
        NavigationStack {
            let m = model.summary.categories[from.id] ?? CategoryMonth()
            Form {
                Section {
                    LabeledContent("Available", value: Money.format(m.available))
                    LabeledContent("Assigned this month", value: Money.format(m.assigned))
                    LabeledContent("Spent", value: Money.format(m.activity))
                }
                Section("Move money") {
                    CategoryPicker(title: "To", selection: $to, allowNone: false)
                    TextField("Amount", text: $amount, prompt: Text(Fmt.edit(max(0, m.available)))).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Button("Move") {
                        if let to, let v = Fmt.parse(amount.isEmpty ? Fmt.edit(max(0, m.available)) : amount) { model.moveMoney(from: from.id, to: to, amount: v) }
                        dismiss()
                    }.disabled(to == nil)
                }
                Section("Widget") {
                    Toggle("Pin to the home-screen widget", isOn: Binding(get: { model.pinned.contains(from.id) }, set: { model.setPinned(from.id, $0) }))
                }
            }.navigationTitle(from.name).navigationBarTitleDisplayMode(.inline).scrollContentBackground(.hidden).background(Theme.background)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}

struct PhoneAccountsView: View {
    let add: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            accountSection("Cash", model.cashAccounts)
            accountSection("Credit", model.creditAccounts)
            accountSection("Tracking", model.trackingAccounts)
            Section("Sync") {
                Text(model.syncStatus).foregroundStyle(Theme.dim)
                if model.syncConfigured {
                    Button(model.syncing ? "Syncing…" : "Sync now") { Task { await model.syncNow() } }.disabled(model.syncing)
                    Button(model.refreshingBank ? "Asking the bank…" : "Refresh bank") { Task { await model.refreshBank() } }.disabled(model.refreshingBank)
                } else { NavigationLink("Set up sync") { PhoneSyncSetupView() } }
            }.listRowBackground(Theme.card)
        }.themedList().navigationTitle("Accounts").toolbar { ToolbarItem(placement: .topBarTrailing) { AddButton(action: add) } }
    }

    @ViewBuilder private func accountSection(_ title: String, _ accounts: [Account]) -> some View {
        if !accounts.isEmpty {
            Section(title) {
                ForEach(accounts, id: \.id) { a in
                    HStack { Text(a.name); Spacer(); Text(Money.format(model.balance(a))).monospacedDigit().foregroundStyle(model.balance(a) < 0 ? Theme.danger : Theme.dim) }
                }.listRowBackground(Theme.card)
            }
        }
    }
}

struct PhoneSyncSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var token = ""

    var body: some View {
        Form {
            TextField("Hub address", text: $url, prompt: Text("http://100.x.y.z:8791")).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            SecureField("Token", text: $token)
            Button("Save and sync") { if model.configureSync(url: url, token: token) { model.startAutoSync(); dismiss() } }.disabled(url.isEmpty || token.isEmpty)
        }.navigationTitle("Sync").scrollContentBackground(.hidden).background(Theme.background)
    }
}

struct PhoneApproveView: View {
    let add: () -> Void
    @Environment(AppModel.self) private var model
    @State private var choosing: CoinboxCore.Transaction?

    var body: some View {
        let rows = model.transactions(TransactionFilter(approved: false))
        Group {
            if rows.isEmpty {
                ContentUnavailableView("All caught up", systemImage: "checkmark.seal", description: Text("New bank activity shows up here to approve."))
            } else {
                List {
                    ForEach(rows) { t in
                        Button { choosing = t } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(title(t)).foregroundStyle(Theme.text).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(Fmt.shortDate(t.date)); Text(model.accountName(t.accountID))
                                        Text(t.categoryID == nil ? "Needs a category" : model.categoryName(t.categoryID)).foregroundStyle(t.categoryID == nil ? Theme.gold : Theme.accent)
                                    }.font(.caption).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                Text(Money.format(t.amount)).monospacedDigit().foregroundStyle(t.amount > 0 ? Theme.done : Theme.text)
                            }
                        }
                        .listRowBackground(Theme.card)
                        .swipeActions(edge: .leading) { if t.categoryID != nil || t.transferPairID != nil { Button("Approve") { model.approve([t.id]) }.tint(Theme.done) } }
                        .swipeActions(edge: .trailing) { Button("Delete", role: .destructive) { model.delete([t.id]) } }
                    }
                }.themedList()
            }
        }
        .navigationTitle("Approve")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { AddButton(action: add) }
            ToolbarItem(placement: .topBarTrailing) {
                let ready = rows.filter { $0.categoryID != nil || $0.transferPairID != nil || !$0.splits.isEmpty }
                Button("Approve \(ready.count)") { model.approve(ready.map(\.id)) }.disabled(ready.isEmpty)
            }
        }
        .sheet(item: $choosing) { PhoneCategorizeView(transaction: $0) }
    }

    private func title(_ t: CoinboxCore.Transaction) -> String {
        let name = model.payeeName(t.payeeID)
        return name.isEmpty ? (t.rawPayee ?? (t.transferPairID != nil ? "Transfer" : "Unknown")) : name
    }
}

struct PhoneCategorizeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let transaction: CoinboxCore.Transaction
    @State private var category: String?
    @State private var payee = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Amount", value: Money.format(transaction.amount))
                    LabeledContent("Date", value: Fmt.shortDate(transaction.date))
                    if let raw = transaction.rawPayee { LabeledContent("From the bank", value: raw) }
                }
                Section {
                    TextField("Payee", text: $payee)
                    if transaction.transferPairID == nil { CategoryPicker(title: "Category", selection: $category) }
                }
                Section {
                    Button("Approve") {
                        var t = transaction
                        t.categoryID = transaction.splits.isEmpty && transaction.transferPairID == nil ? category : transaction.categoryID
                        t.approved = true
                        model.save(t, payeeName: payee)
                        dismiss()
                    }.disabled(category == nil && transaction.transferPairID == nil && transaction.splits.isEmpty)
                }
            }
            .navigationTitle("Approve").navigationBarTitleDisplayMode(.inline).scrollContentBackground(.hidden).background(Theme.background)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .onAppear { category = transaction.categoryID; payee = model.payeeName(transaction.payeeID) }
        }.presentationDetents([.medium, .large])
    }
}

/// Add a cash spend: the amount pad comes first, then payee, category and account.
struct AddTransactionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var cents = 0
    @State private var isOutflow = true
    @State private var payee = ""
    @State private var category: String?
    @State private var accountID: String?
    @State private var chooseCategory = false

    private var amount: Milliunits { Milliunits(cents) * 10 * (isOutflow ? -1 : 1) }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Picker("", selection: $isOutflow) { Text("Spent").tag(true); Text("Received").tag(false) }.pickerStyle(.segmented).frame(width: 180)
                Spacer()
                Color.clear.frame(width: 50)
            }
            Text(Money.format(abs(amount))).font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(cents == 0 ? Theme.faint : isOutflow ? Theme.text : Theme.done)
            VStack(spacing: 8) {
                TextField("Payee", text: $payee).textFieldStyle(.roundedBorder)
                let matches = payee.isEmpty ? [] : model.payees.filter { $0.transferAccountID == nil && $0.name.localizedCaseInsensitiveContains(payee) && $0.name.caseInsensitiveCompare(payee) != .orderedSame }.prefix(3)
                if !matches.isEmpty {
                    HStack { ForEach(Array(matches), id: \.id) { p in Button(p.name) { payee = p.name; if category == nil { category = p.defaultCategoryID } }.buttonStyle(.bordered).controlSize(.small) }; Spacer() }
                }
                HStack {
                    Button { chooseCategory = true } label: { Label(category.map { model.categoryName($0) } ?? "Category", systemImage: "folder").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                    Picker("Account", selection: $accountID) { ForEach(model.openAccounts.filter { $0.onBudget }, id: \.id) { Text($0.name).tag(String?.some($0.id)) } }.labelsHidden()
                }
            }
            Spacer(minLength: 0)
            keypad
            Button { save() } label: { Text("Save").frame(maxWidth: .infinity).font(.headline) }.buttonStyle(.borderedProminent).controlSize(.large).disabled(cents == 0 || accountID == nil)
        }
        .padding(16).background(Theme.background).coinboxTheme()
        .sheet(isPresented: $chooseCategory) {
            NavigationStack {
                Form { CategoryPicker(title: "Category", selection: $category).pickerStyle(.inline) }.navigationTitle("Category").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { chooseCategory = false } } }
            }.presentationDetents([.large])
        }
        .onAppear { accountID = accountID ?? model.cashAccounts.first { $0.kind == .cash }?.id ?? model.cashAccounts.first?.id }
    }

    private var keypad: some View {
        let keys: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["00", "0", "⌫"]]
        return VStack(spacing: 8) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: { Text(key).font(.title2.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52).background(RoundedRectangle(cornerRadius: 12).fill(Theme.field)) }.buttonStyle(.plain).foregroundStyle(Theme.text)
                    }
                }
            }
        }
    }

    private func press(_ key: String) {
        switch key {
        case "⌫": cents /= 10
        case "00": if cents < 10_000_000 { cents *= 100 }
        default: if cents < 100_000_000 { cents = cents * 10 + (Int(key) ?? 0) }
        }
    }

    private func save() {
        guard let accountID else { return }
        model.save(CoinboxCore.Transaction(accountID: accountID, date: Fmt.today(), categoryID: category, amount: amount, cleared: .uncleared, approved: true, author: .iphone), payeeName: payee)
        if model.lastError == nil { dismiss() }
    }
}
#endif
