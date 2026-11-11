#if os(macOS)
import CoinboxCore
import SwiftUI

typealias Tx = CoinboxCore.Transaction

struct RegisterView: View {
    @Environment(AppModel.self) private var model
    let accountID: String?
    @State private var search = ""
    @State private var onlyUnapproved = false
    @State private var selection = Set<String>()
    @State private var editing: Tx?
    @State private var adding = false
    @State private var reconciling = false
    @State private var categorizeTo: String?
    @State private var confirmDelete = false

    private var filter: TransactionFilter { TransactionFilter(accountID: accountID, text: search, approved: onlyUnapproved ? false : nil) }
    private var rows: [Tx] { model.transactions(filter) }
    private var account: Account? { accountID.flatMap { model.account($0) } }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            header(rows)
            Divider().overlay(Theme.line)
            Table(rows, selection: $selection) {
                TableColumn("") { t in statusMark(t) }.width(22)
                TableColumn("Date") { t in Text(t.date).monospacedDigit() }.width(92)
                if accountID == nil { TableColumn("Account") { t in Text(model.accountName(t.accountID)).lineLimit(1) }.width(min: 90, ideal: 120) }
                TableColumn("Payee") { t in payeeCell(t) }
                TableColumn("Category") { t in categoryCell(t) }
                TableColumn("Memo") { t in Text(t.memo ?? "").foregroundStyle(Theme.dim).lineLimit(1) }
                TableColumn("Outflow") { t in Text(t.amount < 0 ? Money.format(-t.amount) : "").monospacedDigit().foregroundStyle(Theme.text) }.width(96)
                TableColumn("Inflow") { t in Text(t.amount > 0 ? Money.format(t.amount) : "").monospacedDigit().foregroundStyle(Theme.done) }.width(96)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if !ids.isEmpty {
                    Button("Approve") { model.approve(Array(ids)) }
                    Menu("Categorize") { categoryMenu(Array(ids)) }
                    Divider()
                    Button("Delete", role: .destructive) { selection = ids; confirmDelete = true }
                }
            } primaryAction: { ids in if let id = ids.first, let t = rows.first(where: { $0.id == id }) { editing = t } }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.background)
        .sheet(item: $editing) { TransactionEditor(transaction: $0, isNew: false) }
        .sheet(isPresented: $adding) { TransactionEditor(transaction: Tx(accountID: accountID ?? model.cashAccounts.first?.id ?? "", date: Fmt.today(), amount: 0, cleared: .uncleared, approved: true), isNew: true) }
        .sheet(isPresented: $reconciling) { if let account { ReconcileSheet(account: account) } }
        .confirmationDialog("Delete \(selection.count) transaction\(selection.count == 1 ? "" : "s")?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.delete(Array(selection)); selection = [] }
        } message: { Text("A transfer's other side is deleted too. You can undo this.") }
    }

    private func header(_ rows: [Tx]) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account?.name ?? "All Transactions").font(.title2.weight(.semibold))
                    if let account {
                        let b = model.balances[account.id] ?? AccountBalance(cleared: 0, uncleared: 0)
                        Text("\(Money.format(b.total)) · cleared \(Money.format(b.cleared))" + (account.lastReconciledDate.map { " · reconciled \($0)" } ?? "")).font(.callout).foregroundStyle(Theme.dim).monospacedDigit()
                    } else { Text("\(rows.count) shown").font(.callout).foregroundStyle(Theme.dim) }
                }
                Spacer()
                if account != nil { Button("Reconcile") { reconciling = true }.buttonStyle(.bordered) }
                Button { adding = true } label: { Label("Add", systemImage: "plus") }.buttonStyle(.borderedProminent).keyboardShortcut("n", modifiers: .command)
            }
            HStack(spacing: 10) {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim); TextField("Search payee, memo, category, amount, date", text: $search).textFieldStyle(.plain) }
                    .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
                Toggle("Needs approval", isOn: $onlyUnapproved).toggleStyle(.checkbox)
                if !selection.isEmpty {
                    Divider().frame(height: 18)
                    Text("\(selection.count) selected").foregroundStyle(Theme.dim)
                    Button("Approve") { model.approve(Array(selection)) }
                    Menu("Categorize") { categoryMenu(Array(selection)) }.menuStyle(.button).fixedSize()
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
            }
        }.padding(16).background(Theme.bar)
    }

    @ViewBuilder private func categoryMenu(_ ids: [String]) -> some View {
        ForEach(model.planGroups, id: \.group.id) { entry in
            Menu(entry.group.name) { ForEach(entry.categories, id: \.id) { c in Button(c.name) { model.categorize(ids, to: c.id) } } }
        }
        Divider()
        Button("Ready to Assign (inflow)") { model.categorize(ids, to: CoinboxCore.Category.readyToAssignID) }
    }

    @ViewBuilder private func statusMark(_ t: Tx) -> some View {
        if !t.approved { Circle().fill(Theme.accent).frame(width: 8, height: 8).help("Needs approval") }
        else if t.cleared == .reconciled { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Theme.dim).help("Reconciled") }
        else if t.cleared == .cleared { Image(systemName: "checkmark").font(.caption2).foregroundStyle(Theme.done).help("Cleared") }
        else { Color.clear }
    }

    private func payeeCell(_ t: Tx) -> some View {
        let name = model.payeeName(t.payeeID)
        return Group {
            if !name.isEmpty { Text(name) }
            else if let raw = t.rawPayee, !raw.isEmpty { Text(raw).foregroundStyle(Theme.dim) }
            else if t.transferPairID != nil { Text("Transfer").foregroundStyle(Theme.dim) }
            else { Text("") }
        }.lineLimit(1)
    }

    private func categoryCell(_ t: Tx) -> some View {
        Group {
            if !t.splits.isEmpty { Text("Split (\(t.splits.count))").foregroundStyle(Theme.accent) }
            else if let c = model.category(t.categoryID) { Text(c.name) }
            else if t.transferPairID != nil { Text("Transfer").foregroundStyle(Theme.dim) }
            else if account?.onBudget == false { Text("") }
            else { Text("Uncategorized").foregroundStyle(Theme.gold) }
        }.lineLimit(1)
    }
}

struct TransactionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    @State private var t: Tx
    @State private var payee = ""
    @State private var amountText = ""
    @State private var isOutflow = true
    @State private var date = Date()
    @State private var splitting = false
    @State private var splitTexts: [String] = []

    init(transaction: Tx, isNew: Bool) { _t = State(initialValue: transaction); self.isNew = isNew }

    private var isTransferLeg: Bool { t.transferPairID != nil }
    private var signed: Milliunits? { Fmt.parse(amountText).map { isOutflow ? -abs($0) : abs($0) } }
    private var splitsTotal: Milliunits { zip(t.splits, splitTexts).reduce(0) { $0 + (Fmt.parse($1.1).map { isOutflow ? -abs($0) : abs($0) } ?? 0) } }
    private var valid: Bool {
        guard let signed, !t.accountID.isEmpty else { return false }
        return !splitting || (t.splits.count >= 2 && splitsTotal == signed && t.splits.allSatisfy { !$0.categoryID.isEmpty })
    }

    var body: some View {
        Form {
            Picker("Account", selection: $t.accountID) { ForEach(model.openAccounts, id: \.id) { Text($0.name).tag($0.id) } }.disabled(!isNew || isTransferLeg)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            if isTransferLeg { LabeledContent("Payee", value: "Transfer") } else {
                TextField("Payee", text: $payee)
                let matches = payee.isEmpty ? [] : model.payees.filter { $0.name.localizedCaseInsensitiveContains(payee) && $0.name.caseInsensitiveCompare(payee) != .orderedSame }.prefix(4)
                if !matches.isEmpty { HStack { ForEach(Array(matches), id: \.id) { p in Button(p.name) { payee = p.name }.buttonStyle(.bordered).controlSize(.small) } }.frame(maxWidth: .infinity, alignment: .leading) }
                if let raw = t.rawPayee, !raw.isEmpty { LabeledContent("From the bank", value: raw).foregroundStyle(Theme.dim) }
            }
            if !splitting && !(model.account(t.accountID)?.onBudget == false && t.categoryID == nil) {
                if isTransferLeg && model.account(t.accountID)?.onBudget == true && t.categoryID == nil { LabeledContent("Category", value: "None (transfer)") }
                else { CategoryPicker(title: "Category", selection: $t.categoryID) }
            }
            TextField("Memo", text: Binding(get: { t.memo ?? "" }, set: { t.memo = $0.isEmpty ? nil : $0 }))
            HStack {
                Picker("", selection: $isOutflow) { Text("Outflow").tag(true); Text("Inflow").tag(false) }.pickerStyle(.segmented).labelsHidden().frame(width: 170).disabled(isTransferLeg)
                TextField("Amount", text: $amountText, prompt: Text("0.00")).multilineTextAlignment(.trailing).disabled(isTransferLeg)
            }
            if !isTransferLeg {
                Toggle("Split between categories", isOn: $splitting.animation()).onChange(of: splitting) { _, on in
                    if on, t.splits.isEmpty { t.splits = [SplitLine(categoryID: t.categoryID ?? "", amount: 0), SplitLine(categoryID: "", amount: 0)]; splitTexts = [amountText, ""]; t.categoryID = nil }
                }
                if splitting {
                    ForEach(t.splits.indices, id: \.self) { i in
                        HStack {
                            CategoryPicker(title: "", selection: Binding(get: { t.splits[i].categoryID.isEmpty ? nil : t.splits[i].categoryID }, set: { t.splits[i].categoryID = $0 ?? "" }), allowNone: false).labelsHidden()
                            TextField("Amount", text: Binding(get: { i < splitTexts.count ? splitTexts[i] : "" }, set: { if i < splitTexts.count { splitTexts[i] = $0 } }))
                                .multilineTextAlignment(.trailing).frame(width: 100)
                        }
                    }
                    HStack {
                        Button("Add line") { t.splits.append(SplitLine(categoryID: "", amount: 0)); splitTexts.append("") }.buttonStyle(.borderless)
                        Spacer()
                        let diff = (signed ?? 0) - splitsTotal
                        Text(diff == 0 ? "Adds up" : "\(Money.format(diff)) left to split").foregroundStyle(diff == 0 ? Theme.done : Theme.gold).font(.callout)
                    }
                }
            }
            Picker("Status", selection: $t.cleared) { Text("Uncleared").tag(ClearedState.uncleared); Text("Cleared").tag(ClearedState.cleared); Text("Reconciled").tag(ClearedState.reconciled) }
            Toggle("Approved", isOn: $t.approved)
            HStack {
                if !isNew { Button("Delete", role: .destructive) { model.delete([t.id]); dismiss() } }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isNew ? "Add" : "Save") { save() }.disabled(!valid).keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped).frame(width: 520).padding()
        .onAppear {
            date = Fmt.date(t.date)
            payee = model.payeeName(t.payeeID)
            isOutflow = t.amount <= 0
            amountText = t.amount == 0 ? "" : Fmt.edit(abs(t.amount))
            if !t.splits.isEmpty { splitting = true; splitTexts = t.splits.map { Fmt.edit(abs($0.amount)) } }
        }
    }

    private func save() {
        guard let signed else { return }
        var out = t
        out.date = Fmt.iso(date)
        out.amount = signed
        if splitting {
            out.categoryID = nil
            out.splits = zip(t.splits, splitTexts).map { SplitLine(categoryID: $0.0.categoryID, amount: Fmt.parse($0.1).map { isOutflow ? -abs($0) : abs($0) } ?? 0, memo: $0.0.memo) }
        } else { out.splits = [] }
        model.save(out, payeeName: isTransferLeg ? model.payeeName(t.payeeID) : payee)
        dismiss()
    }
}

struct ReconcileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let account: Account
    @State private var balance = ""
    @State private var date = Date()
    @State private var adjust = false

    var body: some View {
        let cleared = model.balances[account.id]?.cleared ?? 0
        let bank = Fmt.parse(balance)
        let difference = bank.map { $0 - cleared }
        Form {
            Text("Reconcile \(account.name)").font(.title3.weight(.semibold))
            LabeledContent("Cleared balance here", value: Money.format(cleared)).monospacedDigit()
            TextField("Balance at the bank", text: $balance, prompt: Text("0.00")).multilineTextAlignment(.trailing)
            DatePicker("Statement date", selection: $date, displayedComponents: .date)
            if let difference {
                LabeledContent("Difference") { Text(difference == 0 ? "None. Ready to lock." : Money.format(difference)).foregroundStyle(difference == 0 ? Theme.done : Theme.gold).monospacedDigit() }
                if difference != 0 { Toggle("Add a Reconciliation Balance Adjustment for the difference", isOn: $adjust) }
            }
            Text("Reconciling locks every cleared transaction. Mark transactions cleared in the register first.").font(.footnote).foregroundStyle(Theme.dim)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Reconcile") { if let bank, model.reconcile(accountID: account.id, date: Fmt.iso(date), bankBalance: bank, adjust: adjust) { dismiss() } }
                    .disabled(bank == nil || (difference != 0 && !adjust)).keyboardShortcut(.defaultAction)
            }
        }.formStyle(.grouped).frame(width: 460).padding()
    }
}
#endif
