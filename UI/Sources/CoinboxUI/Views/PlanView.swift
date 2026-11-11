#if os(macOS)
import CoinboxCore
import SwiftUI

struct PlanView: View {
    @Environment(AppModel.self) private var model
    @State private var showHistory = false
    @State private var editing: CoinboxCore.Category?
    @State private var addingTo: CategoryGroup?
    @State private var addingGroup = false
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.planGroups, id: \.group.id) { entry in
                        Section {
                            ForEach(entry.categories, id: \.id) { cat in
                                CategoryRow(category: cat, edit: { editing = cat })
                            }
                            if entry.group.id != CategoryGroup.cardPaymentsID {
                                Button { addingTo = entry.group } label: { Label("Add category", systemImage: "plus") }.buttonStyle(.plain).font(.callout).foregroundStyle(Theme.dim)
                                    .padding(.horizontal, 16).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } header: { groupHeader(entry.group, entry.categories) }
                    }
                    Button { addingGroup = true } label: { Label("Add category group", systemImage: "plus.rectangle.on.rectangle") }.buttonStyle(.plain).foregroundStyle(Theme.accent).padding(16)
                }
            }
        }
        .background(Theme.background)
        .sheet(item: $editing) { CategorySheet(category: $0) }
        .sheet(item: $addingTo) { g in NameSheet(title: "New category in \(g.name)") { model.addCategory($0, in: g.id) } }
        .sheet(isPresented: $addingGroup) { NameSheet(title: "New category group") { model.addGroup($0) } }
        .sheet(isPresented: $showHistory) { MoneyMovesSheet() }
        .onAppear { note = model.monthNote }
        .onChange(of: model.month) { _, _ in note = model.monthNote }
        .onChange(of: model.monthNote) { _, new in if new != note { note = new } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Button { model.month = model.month.previous } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                    Text(model.month.title).font(.title2.weight(.semibold)).frame(minWidth: 170)
                    Button { model.month = model.month.next } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                    if model.month != MonthKey.current() { Button("Today") { model.month = MonthKey.current() }.buttonStyle(.borderless).foregroundStyle(Theme.accent) }
                }
                Spacer()
                runwayView
                rtaView
            }.padding(.horizontal, 16)
            HStack(spacing: 10) {
                TextField("Note for \(model.month.title)", text: $note).textFieldStyle(.plain).padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
                    .onSubmit { model.setMonthNote(month: model.month.string, text: note) }
                Button("Auto-assign underfunded") { model.autoAssign() }.buttonStyle(.bordered)
                Button("Money moves") { showHistory = true }.buttonStyle(.bordered)
            }.padding(.horizontal, 16)
            HStack {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                Text("Assigned").frame(width: 110, alignment: .trailing)
                Text("Activity").frame(width: 110, alignment: .trailing)
                Text("Available").frame(width: 120, alignment: .trailing)
            }.font(.caption.weight(.semibold)).foregroundStyle(Theme.dim).padding(.horizontal, 16)
        }
        .padding(.top, 16).background(Theme.bar)
    }

    private var rtaView: some View {
        let rta = model.summary.readyToAssign
        return VStack(alignment: .trailing, spacing: 2) {
            Pill(text: Money.format(rta), fill: rta < 0 ? Theme.danger : rta == 0 ? Theme.raised : Theme.done, foreground: rta == 0 ? Theme.dim : Theme.background).font(.title3)
            Text(rta < 0 ? "Overassigned" : "Ready to Assign").font(.caption).foregroundStyle(rta < 0 ? Theme.danger : Theme.dim)
        }
    }

    private var runwayView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(model.runway.months.map { String(format: "%.1f months", $0) } ?? "No targets yet").font(.headline).monospacedDigit()
            Text("Runway · \(Money.format(model.runway.costToBeMe)) a month to be me").font(.caption).foregroundStyle(Theme.dim)
        }
        .help("Cash in your on-budget cash accounts divided by what your targets say a month costs.")
    }

    private func groupHeader(_ g: CategoryGroup, _ cats: [CoinboxCore.Category]) -> some View {
        let sums = cats.compactMap { model.summary.categories[$0.id] }
        return HStack {
            Text(g.name).font(.subheadline.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
            Text(Money.format(sums.reduce(0) { $0 + $1.assigned })).frame(width: 110, alignment: .trailing)
            Text(Money.format(sums.reduce(0) { $0 + $1.activity })).frame(width: 110, alignment: .trailing)
            Text(Money.format(sums.reduce(0) { $0 + $1.available })).frame(width: 120, alignment: .trailing)
        }
        .font(.subheadline).monospacedDigit().foregroundStyle(Theme.dim).padding(.horizontal, 16).padding(.vertical, 6).background(Theme.card)
    }
}

struct CategoryRow: View {
    @Environment(AppModel.self) private var model
    let category: CoinboxCore.Category
    let edit: () -> Void
    @State private var assignedText = ""
    @State private var showMove = false
    @State private var showActivity = false
    @FocusState private var focused: Bool

    private var m: CategoryMonth { model.summary.categories[category.id] ?? CategoryMonth() }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(category.name).lineLimit(1)
                    if category.note?.isEmpty == false { Image(systemName: "note.text").font(.caption).foregroundStyle(Theme.dim).help(category.note ?? "") }
                    if case .cardPayment = category.kind, m.underfunded > 0 { Text("underfunded \(Money.format(m.underfunded))").font(.caption).foregroundStyle(Theme.gold) }
                    else if m.underfunded > 0 { Text("needs \(Money.format(m.underfunded))").font(.caption).foregroundStyle(Theme.gold) }
                }
                if let p = progress { ProgressView(value: p).tint(p >= 1 ? Theme.done : Theme.accent).frame(maxWidth: 220) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField("0.00", text: $assignedText).textFieldStyle(.plain).multilineTextAlignment(.trailing).monospacedDigit().padding(.vertical, 4).padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(focused ? Theme.field : .clear)).frame(width: 110).focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { _, now in if !now { commit() } }
                .disabled(category.kind == .cardInterest)
            Button { showActivity = true } label: { Text(Money.format(m.activity)).monospacedDigit().foregroundStyle(m.activity == 0 ? Theme.faint : Theme.text) }
                .buttonStyle(.plain).frame(width: 110, alignment: .trailing)
                .popover(isPresented: $showActivity) { ActivityList(category: category) }
            Button { if category.kind != .cardInterest { showMove = true } } label: { availablePill }
                .buttonStyle(.plain).frame(width: 120, alignment: .trailing)
                .popover(isPresented: $showMove) { MoveMoneySheet(from: category) }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Move up") { model.move(category, by: -1) }
            Button("Move down") { model.move(category, by: 1) }
            Button(category.hidden ? "Show" : "Hide") { var c = category; c.hidden.toggle(); model.update(c) }
        }
        .onAppear { sync() }
        .onChange(of: m.assigned) { _, _ in if !focused { sync() } }
        .onChange(of: model.month) { _, _ in sync() }
    }

    private func sync() { assignedText = m.assigned == 0 ? "" : Fmt.edit(m.assigned) }

    private func commit() {
        let value = Fmt.parse(assignedText) ?? m.assigned
        if value != m.assigned { model.setAssigned(category.id, value) }
        sync()
    }

    @ViewBuilder private var availablePill: some View {
        if category.kind == .cardInterest { Text("").frame(width: 1) }
        else if m.cashOverspent > 0 { Pill(text: Money.format(m.available), fill: Theme.danger) }
        else if m.creditOverspent > 0 { Pill(text: Money.format(m.available), fill: Theme.gold) }
        else if m.available > 0 { Pill(text: Money.format(m.available), fill: Theme.done) }
        else { Pill(text: Money.format(m.available), fill: Theme.raised, foreground: Theme.dim) }
    }

    private var progress: Double? {
        if case .cardPayment = category.kind {
            let total = m.available + m.underfunded
            return total > 0 ? Double(m.available) / Double(total) : nil
        }
        guard let t = model.targets[category.id] else { return nil }
        let needed = TargetMath.needed(t, in: model.month, carryover: m.carryover)
        guard needed > 0 else { return 1 }
        return min(1, max(0, Double(m.assigned) / Double(needed)))
    }
}

struct ActivityList: View {
    @Environment(AppModel.self) private var model
    let category: CoinboxCore.Category
    var body: some View {
        let txs = model.transactions(TransactionFilter(categoryID: category.id, from: model.month.firstDay, to: model.month.lastDay))
        VStack(alignment: .leading, spacing: 6) {
            Text("\(category.name) in \(model.month.title)").font(.headline)
            if txs.isEmpty { Text("No transactions.").foregroundStyle(Theme.dim) }
            ForEach(txs.prefix(40)) { t in
                HStack { Text(Fmt.shortDate(t.date)).frame(width: 52, alignment: .leading); Text(model.payeeName(t.payeeID).isEmpty ? (t.rawPayee ?? "") : model.payeeName(t.payeeID)).lineLimit(1)
                    Spacer(minLength: 20); Text(Money.format(t.splits.first { $0.categoryID == category.id }?.amount ?? t.amount)).monospacedDigit() }.font(.callout)
            }
            if category.kind != .normal, case .cardPayment = category.kind { Text("Card spending moves here as it's covered; payments come out.").font(.caption).foregroundStyle(Theme.dim) }
        }.padding(14).frame(width: 380)
    }
}

struct MoveMoneySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let from: CoinboxCore.Category
    @State private var to: String?
    @State private var amount = ""

    var body: some View {
        let available = model.summary.categories[from.id]?.available ?? 0
        VStack(alignment: .leading, spacing: 10) {
            Text("Move money from \(from.name)").font(.headline)
            Text("\(Money.format(available)) available").foregroundStyle(Theme.dim).font(.callout)
            CategoryPicker(title: "To", selection: $to, allowNone: false)
            TextField("Amount", text: $amount, prompt: Text(Fmt.edit(max(0, available)))).multilineTextAlignment(.trailing)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Move") {
                    if let to, let v = Fmt.parse(amount.isEmpty ? Fmt.edit(max(0, available)) : amount) { model.moveMoney(from: from.id, to: to, amount: v) }
                    dismiss()
                }.disabled(to == nil).keyboardShortcut(.defaultAction)
            }
        }.padding(14).frame(width: 340)
    }
}

struct NameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let save: (String) -> Void
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Name", text: $name).onSubmit(done)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Add", action: done).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).keyboardShortcut(.defaultAction) }
        }.padding(16).frame(width: 340)
    }
    private func done() { let n = name.trimmingCharacters(in: .whitespaces); if !n.isEmpty { save(n); dismiss() } }
}

struct MoneyMovesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Money moves in \(model.month.title)").font(.title3.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
            if model.moves.isEmpty { Text("Nothing has been assigned or moved this month.").foregroundStyle(Theme.dim) }
            List(model.moves, id: \.changeID) { mv in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(Date(timeIntervalSince1970: TimeInterval(mv.createdAt) / 1000).formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Theme.dim)
                        Text("by \(mv.author.rawValue)").foregroundStyle(Theme.dim)
                        if mv.undone { Text("undone").foregroundStyle(Theme.gold) }
                    }.font(.caption)
                    ForEach(mv.lines, id: \.self) { l in
                        HStack { Text(model.categoryName(l.categoryID)); Spacer(); Text((l.delta > 0 ? "+" : "") + Money.format(l.delta)).monospacedDigit().foregroundStyle(l.delta < 0 ? Theme.danger : Theme.done) }.font(.callout)
                    }
                }.padding(.vertical, 3).opacity(mv.undone ? 0.5 : 1)
            }.themedList()
        }.padding(16).frame(width: 520, height: 460)
    }
}

struct CategorySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var category: CoinboxCore.Category
    @State private var note = ""
    @State private var kind = "none"
    @State private var amount = ""
    @State private var weekday = 1
    @State private var day = 1
    @State private var month = 1
    @State private var date = Date()
    @State private var every = 3

    init(category: CoinboxCore.Category) { _category = State(initialValue: category) }

    var body: some View {
        Form {
            TextField("Name", text: $category.name)
            Toggle("Hidden", isOn: $category.hidden)
            TextField("Note", text: $note, axis: .vertical).lineLimit(2...4)
            if category.kind == .normal {
                Section("Target") {
                    Picker("Needs", selection: $kind) {
                        Text("No target").tag("none"); Text("A set amount every month").tag("monthly"); Text("A set amount every week").tag("weekly")
                        Text("Once a year").tag("yearly"); Text("By a date").tag("byDate"); Text("Every few months").tag("every")
                    }
                    if kind != "none" { TextField("Amount", text: $amount).multilineTextAlignment(.trailing) }
                    switch kind {
                    case "monthly": Stepper("On day \(day)", value: $day, in: 1...31)
                    case "weekly": Picker("Weekday", selection: $weekday) { ForEach(1...7, id: \.self) { Text(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][$0 - 1]).tag($0) } }
                    case "yearly": Picker("Month", selection: $month) { ForEach(1...12, id: \.self) { Text(MonthKey(year: 2026, month: $0).title.split(separator: " ")[0]).tag($0) } }; Stepper("On day \(day)", value: $day, in: 1...31)
                    case "byDate": DatePicker("Due", selection: $date, displayedComponents: .date)
                    case "every": Stepper("Every \(every) months", value: $every, in: 2...36); DatePicker("Next due", selection: $date, displayedComponents: .date)
                    default: EmptyView()
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save(); dismiss() }.keyboardShortcut(.defaultAction).disabled(category.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped).frame(width: 440).padding()
        .onAppear { load() }
    }

    private func load() {
        note = category.note ?? ""
        guard let t = model.targets[category.id] else { return }
        amount = Fmt.edit(t.amount)
        switch t.cadence {
        case let .monthly(d): kind = "monthly"; day = d
        case let .weekly(w): kind = "weekly"; weekday = w
        case let .yearly(m, d): kind = "yearly"; month = m; day = d
        case let .byDate(d): kind = "byDate"; date = Fmt.date(d)
        case let .everyMonths(n, d): kind = "every"; every = n; date = Fmt.date(d)
        }
    }

    private func save() {
        category.note = note.isEmpty ? nil : note
        model.update(category)
        guard category.kind == .normal else { return }
        let cadence: Cadence? = {
            switch kind {
            case "monthly": return .monthly(day: day)
            case "weekly": return .weekly(isoWeekday: weekday)
            case "yearly": return .yearly(month: month, day: day)
            case "byDate": return .byDate(Fmt.iso(date))
            case "every": return .everyMonths(n: every, firstDue: Fmt.iso(date))
            default: return nil
            }
        }()
        if let cadence, let v = Fmt.parse(amount), v > 0 { model.setTarget(Target(categoryID: category.id, cadence: cadence, amount: v), for: category.id) }
        else { model.setTarget(nil, for: category.id) }
    }
}
#endif
