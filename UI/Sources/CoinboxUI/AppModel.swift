import CoinboxCore
import Foundation
import Observation

/// Everything the screens show, plus the actions that change it. Reloads from the database after each action
/// and when another process (the `coinbox` CLI, Claude's tools) changes the file.
@MainActor @Observable
public final class AppModel {
    public let coinbox: Coinbox
    public private(set) var monthNotes: [MonthNote] = []
    public private(set) var accounts: [Account] = []
    public private(set) var groups: [CategoryGroup] = []
    public private(set) var categories: [CoinboxCore.Category] = []
    public private(set) var payees: [Payee] = []
    public private(set) var rules: [Rule] = []
    public private(set) var targets: [String: Target] = [:]
    public private(set) var balances: [String: AccountBalance] = [:]
    public private(set) var summary = MonthSummary(month: MonthKey(year: 2026, month: 1), readyToAssign: 0, categories: [:], cashOverspending: 0)
    public private(set) var runway = Runway(cash: 0, costToBeMe: 0, months: nil)
    public private(set) var moves: [MoneyMove] = []
    public private(set) var unapprovedCount = 0
    public private(set) var canUndo = false
    public private(set) var canRedo = false
    public private(set) var syncStatus = "Not set up"
    public private(set) var syncing = false
    public private(set) var refreshingBank = false
    public var lastError: String?
    /// Who made changes made here: the Mac app, or the phone.
    public var author: Author = {
        #if os(iOS)
        .iphone
        #else
        .mac
        #endif
    }()
    public private(set) var pinned: [String] = []
    public private(set) var cardTerms: [String: CardTerms] = [:]
    /// Where the iPhone app's widget reads its pinned categories (an App Group suite); nil on the Mac.
    @ObservationIgnored public var widgetDefaults: UserDefaults?
    public var month: MonthKey { didSet { if month != oldValue { defaults.set(month.string, forKey: "month"); reload() } } }

    @ObservationIgnored private let databasePath: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var autoSync: Task<Void, Never>?
    @ObservationIgnored private var lastDataVersion = 0
    @ObservationIgnored private var categoryByID: [String: CoinboxCore.Category] = [:]
    @ObservationIgnored private var payeeByID: [String: Payee] = [:]
    @ObservationIgnored private var accountByID: [String: Account] = [:]

    public init(coinbox: Coinbox, databasePath: String? = nil, defaults: UserDefaults = .standard) {
        self.coinbox = coinbox
        self.databasePath = databasePath
        self.defaults = defaults
        month = defaults.string(forKey: "month").flatMap(MonthKey.init) ?? MonthKey.current()
        lastDataVersion = (try? coinbox.dataVersion()) ?? 0
        reload()
    }

    /// The database the app and the `coinbox` CLI share: `$COINBOX_DB`, else Application Support/Coinbox/coinbox.sqlite.
    public static func openDefault() throws -> AppModel {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Coinbox", isDirectory: true)
        let path = ProcessInfo.processInfo.environment["COINBOX_DB"] ?? dir.appendingPathComponent("coinbox.sqlite").path
        return try open(path: path)
    }

    /// Opens (or creates) the database at `path`. A new database is given its own device name, which sync relies on being unique
    /// to each install; an existing one keeps the name it was created with.
    public static func open(path: String) throws -> AppModel {
        let coinbox = try Coinbox.open(path: path, device: "app-" + UUID().uuidString.prefix(8).lowercased())
        return AppModel(coinbox: coinbox, databasePath: path)
    }

    // MARK: loading

    public func reload() {
        do {
            monthNotes = try coinbox.monthNotes()
            accounts = try coinbox.accounts()
            groups = try coinbox.categoryGroups()
            categories = try coinbox.categories()
            payees = try coinbox.payees()
            rules = try coinbox.rules()
            targets = Dictionary(try coinbox.targets().map { ($0.categoryID, $0) }, uniquingKeysWith: { a, _ in a })
            balances = try coinbox.accountBalances()
            summary = try coinbox.budget(for: month)
            runway = try coinbox.runway(asOf: month)
            moves = try coinbox.moneyMoves(month: month.string)
            unapprovedCount = try coinbox.search(TransactionFilter(approved: false)).count
            cardTerms = Dictionary(try coinbox.cardTerms().map { ($0.accountID, $0) }, uniquingKeysWith: { a, _ in a })
            pinned = widgetDefaults?.stringArray(forKey: "pinned") ?? []
            canRedo = try coinbox.canRedo()
            canUndo = try !coinbox.changes(since: 0, author: nil).filter { !$0.undone }.isEmpty
            categoryByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            payeeByID = Dictionary(payees.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            accountByID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        } catch { lastError = "\(error)" }
    }

    /// Reloads if another process has written to the file since the last check; returns whether it did.
    @discardableResult
    public func reloadIfChanged() -> Bool {
        let version = (try? coinbox.dataVersion()) ?? lastDataVersion
        guard version != lastDataVersion else { return false }
        lastDataVersion = version
        reload()
        return true
    }

    public func startWatching(interval: TimeInterval = 1) {
        watcher?.cancel()
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self else { return }
                self.reloadIfChanged()
            }
        }
    }

    public func stopWatching() { watcher?.cancel(); watcher = nil }

    // MARK: lookups

    public func category(_ id: String?) -> CoinboxCore.Category? { id.flatMap { categoryByID[$0] } }
    public func categoryName(_ id: String?) -> String { id.flatMap { categoryByID[$0]?.name } ?? "" }
    public func payeeName(_ id: String?) -> String { id.flatMap { payeeByID[$0]?.name } ?? "" }
    public func accountName(_ id: String) -> String { accountByID[id]?.name ?? id }
    public func account(_ id: String) -> Account? { accountByID[id] }

    /// The groups and categories the plan lists: visible ones, in order, without the built-in Inflow group.
    public var planGroups: [(group: CategoryGroup, categories: [CoinboxCore.Category])] {
        groups.filter { !$0.hidden && $0.id != CategoryGroup.inflowID }.compactMap { g in
            let cats = categories.filter { $0.groupID == g.id && !$0.hidden && $0.kind != .readyToAssign }
            return cats.isEmpty && g.id == CategoryGroup.cardPaymentsID ? nil : (g, cats)
        }
    }

    public var openAccounts: [Account] { accounts.filter { !$0.closed } }
    public var cashAccounts: [Account] { openAccounts.filter { $0.onBudget && $0.kind != .creditCard } }
    public var creditAccounts: [Account] { openAccounts.filter { $0.onBudget && $0.kind == .creditCard } }
    public var trackingAccounts: [Account] { openAccounts.filter { !$0.onBudget } }
    public func total(_ accounts: [Account]) -> Milliunits { accounts.reduce(0) { $0 + (balances[$1.id]?.total ?? 0) } }
    public func balance(_ account: Account) -> Milliunits { balances[account.id]?.total ?? 0 }

    public func transactions(_ filter: TransactionFilter) -> [Transaction] { (try? coinbox.search(filter)) ?? [] }

    public var monthNote: String { monthNotes.first { $0.month == month.string }?.text ?? "" }

    // MARK: actions

    /// Runs ops as one undoable change by the Mac, then reloads. Returns whether it worked; the message lands in `lastError`.
    @discardableResult
    public func perform(_ ops: [Op]) -> Bool {
        guard !ops.isEmpty else { return true }
        do { try coinbox.perform(ops, author: author); reload(); return true } catch {
            lastError = (error as? CoinboxError)?.message ?? "\(error)"
            reload()
            return false
        }
    }

    public func setMonthNote(month: String, text: String) { perform(text.isEmpty ? (monthNotes.contains { $0.month == month } ? [.deleteMonthNote(month: month)] : []) : [.putMonthNote(MonthNote(month: month, text: text))]) }

    /// Sets what a category is assigned this month.
    public func setAssigned(_ categoryID: String, _ amount: Milliunits) {
        perform([.putAssignment(Assignment(categoryID: categoryID, month: month.string, amount: amount))])
    }

    /// Sets what a category is assigned in any month (the review screen plans the month after the one it shows).
    public func setAssigned(_ categoryID: String, month: MonthKey, _ amount: Milliunits) {
        perform([.putAssignment(Assignment(categoryID: categoryID, month: month.string, amount: amount))])
    }

    /// How `month` went next to the month after's plan. Reads `summary` so views showing it refresh after every change.
    public func review(_ month: MonthKey) -> MonthReview? {
        _ = summary
        return try? coinbox.monthReview(month)
    }

    public func moveMoney(from: String, to: String, amount: Milliunits) {
        guard amount > 0, from != to else { return }
        let a = summary.categories[from]?.assigned ?? 0, b = summary.categories[to]?.assigned ?? 0
        perform([.putAssignment(Assignment(categoryID: from, month: month.string, amount: a - amount)), .putAssignment(Assignment(categoryID: to, month: month.string, amount: b + amount))])
    }

    public func autoAssign() {
        do { perform(try coinbox.autoAssignOps(month: month).ops) } catch { lastError = "\(error)" }
    }

    public func undo() {
        do { try coinbox.undo(author: nil); reload() } catch { lastError = "\(error)" }
    }

    public func redo() {
        do { try coinbox.redo(author: author); reload() } catch { lastError = "\(error)" }
    }

    // Categories and groups

    public func addGroup(_ name: String) {
        perform([.putCategoryGroup(CategoryGroup(name: name, order: (groups.map(\.order).max() ?? 0) + 1))])
    }

    public func addCategory(_ name: String, in groupID: String) {
        perform([.putCategory(CoinboxCore.Category(groupID: groupID, name: name, order: (categories.filter { $0.groupID == groupID }.map(\.order).max() ?? 0) + 1))])
    }

    public func update(_ c: CoinboxCore.Category) { perform([.putCategory(c)]) }
    public func update(_ g: CategoryGroup) { perform([.putCategoryGroup(g)]) }

    public func setTarget(_ t: Target?, for categoryID: String) {
        perform([t.map { Op.putTarget($0) } ?? .deleteTarget(categoryID: categoryID)].filter { op in
            if case .deleteTarget = op { return targets[categoryID] != nil }
            return true
        })
    }

    /// Puts a category one place earlier or later within its group.
    public func move(_ c: CoinboxCore.Category, by step: Int) {
        let siblings = categories.filter { $0.groupID == c.groupID }.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
        guard let i = siblings.firstIndex(where: { $0.id == c.id }), siblings.indices.contains(i + step) else { return }
        var reordered = siblings
        reordered.swapAt(i, i + step)
        perform(reordered.enumerated().compactMap { n, cat in cat.order == n ? nil : .putCategory({ var u = cat; u.order = n; return u }()) })
    }

    // Accounts

    public func addAccount(name: String, kind: AccountKind, onBudget: Bool, startingBalance: Milliunits, date: String) {
        let account = Account(name: name, kind: kind, onBudget: onBudget)
        var ops = Coinbox.createAccountOps(account)
        if startingBalance != 0 {
            let toRTA = onBudget && kind != .creditCard && startingBalance > 0
            ops.append(.putTransaction(Transaction(accountID: account.id, date: date, categoryID: toRTA ? CoinboxCore.Category.readyToAssignID : nil, memo: "Starting Balance",
                                                   amount: startingBalance, cleared: .reconciled, approved: true, author: author)))
        }
        perform(ops)
    }

    public func update(_ a: Account) { perform([.putAccount(a)]) }

    /// APR (percent) and minimum payment for a card; the planner needs both.
    public func setTerms(accountID: String, aprPercent: Decimal, minimum: Milliunits) {
        let basis = Int(truncating: NSDecimalNumber(decimal: aprPercent * 100).rounding(accordingToBehavior: nil))
        perform([.putCardTerms(CardTerms(accountID: accountID, aprBasisPoints: basis, minimumPayment: minimum))])
    }

    public func payoff(strategy: PayoffStrategy, monthlyBudget: Milliunits) -> PayoffPlan? {
        do { return try coinbox.payoffPlan(strategy: strategy, monthlyBudget: monthlyBudget, start: MonthKey.current()) } catch { lastError = "\(error)"; return nil }
    }

    /// Pins a category to the home-screen widget (up to four).
    public func setPinned(_ categoryID: String, _ on: Bool) {
        var list = pinned.filter { $0 != categoryID }
        if on { list.append(categoryID) }
        widgetDefaults?.set(Array(list.suffix(4)), forKey: "pinned")
        pinned = Array(list.suffix(4))
    }

    public func reconcile(accountID: String, date: String, bankBalance: Milliunits, adjust: Bool) -> Bool {
        do { return perform(try coinbox.reconcileOps(accountID: accountID, date: date, bankBalance: bankBalance, adjust: adjust, author: author)) }
        catch { lastError = (error as? CoinboxError)?.message ?? "\(error)"; return false }
    }

    // Transactions

    /// A payee with this name, creating it if it's new. Returns the id and any op needed to create it.
    private func payee(named name: String) -> (id: String?, ops: [Op]) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (nil, []) }
        if let p = payees.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return (p.id, []) }
        let p = Payee(name: trimmed)
        return (p.id, [.putPayee(p)])
    }

    /// Saves a transaction, creating the payee typed into the name field if it doesn't exist. A payee with a default category fills
    /// an empty category.
    public func save(_ transaction: Transaction, payeeName: String) {
        var t = transaction
        let (pid, ops) = payee(named: payeeName)
        t.payeeID = pid
        if t.categoryID == nil, t.splits.isEmpty, t.transferPairID == nil, let pid, let d = payeeByID[pid]?.defaultCategoryID { t.categoryID = d }
        perform(ops + [.putTransaction(t)])
    }

    public func approve(_ ids: [String]) { if let b = try? coinbox.planApprove(ids: ids) { perform(b.ops) } }
    public func categorize(_ ids: [String], to categoryID: String, approve: Bool = true) { if let b = try? coinbox.planCategorize(ids: ids, categoryID: categoryID, approve: approve) { reportSkips(b); perform(b.ops) } }
    public func delete(_ ids: [String]) { if let b = try? coinbox.planDelete(ids: ids) { perform(b.ops) } }

    private func reportSkips(_ b: PlannedBatch) {
        let skipped = b.changes.compactMap(\.skipped)
        if !skipped.isEmpty { lastError = skipped.count == 1 ? skipped[0] : "\(skipped.count) transactions were left alone: \(skipped[0])" }
    }

    public func transfer(date: String, from: String, to: String, amount: Milliunits, categoryID: String?) {
        do { perform(try coinbox.transferOps(id: UUID().uuidString.lowercased(), date: date, from: from, to: to, amount: amount, categoryID: categoryID, author: author)) }
        catch { lastError = (error as? CoinboxError)?.message ?? "\(error)" }
    }

    // Rules and payees

    public func save(_ r: Rule) { perform([.putRule(r)]) }
    public func deleteRule(_ id: String) { perform([.deleteRule(id: id)]) }

    /// Rewrites every rule's order to match `ordered`.
    public func reorder(_ ordered: [Rule]) { perform(ordered.enumerated().map { i, r in .putRule({ var u = r; u.order = i; return u }()) }) }

    public func applyRules() {
        do { let b = try coinbox.planRuleApplication(); reportSkips(b); perform(b.ops) } catch { lastError = "\(error)" }
    }

    public func save(_ p: Payee) { perform([.putPayee(p)]) }

    // MARK: sync

    private var syncConfig: SyncConfig? { databasePath.flatMap { SyncConfig.load(besideDatabaseAt: $0) } }
    public var syncConfigured: Bool { syncConfig != nil }

    public func configureSync(url: String, token: String) -> Bool {
        guard let databasePath, let parsed = URL(string: url), parsed.scheme != nil, parsed.host != nil, !token.isEmpty else { lastError = "The hub address should look like http://100.x.y.z:8791, with a token."; return false }
        do { try SyncConfig(url: parsed, token: token).save(besideDatabaseAt: databasePath); syncStatus = "Set up"; return true } catch { lastError = "\(error)"; return false }
    }

    public func syncNow() async {
        guard let config = syncConfig else { syncStatus = "Not set up"; return }
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let report = try await SyncClient(coinbox: coinbox, transport: config.transport()).sync()
            syncStatus = "Synced \(Date.now.formatted(date: .omitted, time: .shortened))" + (report.failed > 0 ? " (\(report.failed) changes couldn't be applied)" : "")
            reload()
        } catch { syncStatus = "Couldn't sync: \((error as? CoinboxError)?.message ?? error.localizedDescription)" }
    }

    /// Asks the hub to pull bank activity now, then syncs to bring it here.
    public func refreshBank() async {
        guard let config = syncConfig else { lastError = "Set up sync first."; return }
        guard !refreshingBank else { return }
        refreshingBank = true
        defer { refreshingBank = false }
        var request = URLRequest(url: config.url.appendingPathComponent("simplefin/refresh"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        if let host = config.hostHeader { request.setValue(host, forHTTPHeaderField: "Host") }
        request.timeoutInterval = 120
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 { lastError = "The hub refreshed less than a minute ago." } else if status != 200 { lastError = "The hub said \(status): \(String(decoding: data.prefix(200), as: UTF8.self))" }
        } catch { lastError = "Couldn't reach the hub: \(error.localizedDescription)" }
        await syncNow()
    }

    public func startAutoSync(interval: TimeInterval = 60) {
        autoSync?.cancel()
        guard syncConfigured else { return }
        autoSync = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }
}

extension MonthKey {
    /// This calendar month, in the local time zone.
    public static func current() -> MonthKey {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return MonthKey(year: c.year ?? 2026, month: c.month ?? 1)
    }

    /// "January 2026".
    public var title: String {
        let names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        return "\(names[month - 1]) \(year)"
    }
}
