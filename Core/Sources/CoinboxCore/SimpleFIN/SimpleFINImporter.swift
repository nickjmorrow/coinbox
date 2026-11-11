import Foundation

public struct SimpleFINReport: Codable, Sendable, Equatable {
    public struct Balance: Codable, Sendable, Equatable {
        public var account: String
        public var simplefin: Milliunits
        public var coinbox: Milliunits
    }

    public var fetchedAccounts = 0
    public var newTransactions = 0
    public var matchedExisting = 0
    public var linkedTransfers = 0
    public var skippedPending = 0
    public var skippedUnreadable = 0
    public var rulesApplied = 0
    public var unlinkedAccounts: [String] = []
    public var ambiguousTransfers: [String] = []
    public var bridgeMessages: [String] = []
    public var balances: [Balance] = []

    public init() {}
}

extension Coinbox {
    /// Plans what a SimpleFIN response adds: new unapproved rows, bank ids attached to rows YNAB or a person already recorded, and card
    /// payments linked to their checking side. Plans only.
    public func planSimpleFINImport(_ response: SFResponse, timeZone: TimeZone) throws -> (ops: [Op], report: SimpleFINReport) {
        var report = SimpleFINReport()
        report.fetchedAccounts = response.accounts.count
        report.bridgeMessages = response.errors.map(SimpleFIN.redact)
        let accounts = Dictionary(try self.accounts().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let bySF = Dictionary(accounts.values.compactMap { a in a.simplefinID.map { ($0, a) } }, uniquingKeysWith: { a, _ in a })
        let existing = try transactions()
        var all: [String: Transaction] = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var knownBankIDs = Set(existing.compactMap(\.bankImportID))
        var touched: [String] = []                // ids in the order they were first changed
        var newIDs: [String] = []
        var usedExisting = Set<String>()
        func put(_ t: Transaction) { if all[t.id] == nil || !touched.contains(t.id) { touched.append(t.id) }; all[t.id] = t }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func dateString(_ epoch: Int64) -> String {
            let c = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(epoch)))
            return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        }
        func dayGap(_ a: String, _ b: String) -> Int { abs((MonthKey.dayNumber(a) ?? 0) - (MonthKey.dayNumber(b) ?? 0)) }

        for sf in response.accounts {
            guard let account = bySF[sf.id] else { report.unlinkedAccounts.append([sf.orgName, sf.name].compactMap { $0 }.joined(separator: " ")); continue }
            for tx in sf.transactions.sorted(by: { ($0.posted, $0.id) < ($1.posted, $1.id) }) {
                if tx.pending { report.skippedPending += 1; continue }
                guard let amount = SimpleFIN.parseAmount(tx.amount) else { report.skippedUnreadable += 1; continue }
                let bankID = "sf:\(sf.id):\(tx.id)"
                if knownBankIDs.contains(bankID) { continue }
                knownBankIDs.insert(bankID)
                let date = dateString(tx.posted)
                let near = all.values.filter { $0.accountID == account.id && $0.amount == amount && $0.bankImportID == nil && !usedExisting.contains($0.id) && dayGap($0.date, date) <= 4 }
                    .min { (dayGap($0.date, date), $0.id) < (dayGap($1.date, date), $1.id) }
                if var match = near {
                    match.bankImportID = bankID
                    if match.rawPayee == nil { match.rawPayee = tx.description }
                    usedExisting.insert(match.id)
                    put(match)
                    report.matchedExisting += 1
                } else {
                    let t = Transaction(id: "sf-\(sf.id)-\(tx.id)", accountID: account.id, date: date, memo: tx.memo, amount: amount, cleared: .cleared, approved: false,
                                        bankImportID: bankID, rawPayee: tx.description, author: .bank)
                    put(t)
                    newIDs.append(t.id)
                    report.newTransactions += 1
                }
            }
        }

        // Card payments: the card's inflow and the checking outflow of exactly the same amount, a few days apart, are one transfer.
        func isCard(_ t: Transaction) -> Bool { accounts[t.accountID]?.kind == .creditCard }
        func onBudget(_ t: Transaction) -> Bool { accounts[t.accountID]?.onBudget == true }
        /// Unpaired bank rows that could be the other side of `t`, nearest date first.
        func partners(of t: Transaction) -> [Transaction] {
            guard onBudget(t), (isCard(t) && t.amount > 0) || (!isCard(t) && t.amount < 0) else { return [] }
            return all.values.filter { c in
                c.id != t.id && c.transferPairID == nil && c.bankImportID != nil && c.amount == -t.amount && onBudget(c) && c.accountID != t.accountID
                    && (isCard(t) ? !isCard(c) : isCard(c)) && dayGap(c.date, t.date) <= 5
            }.sorted { (dayGap($0.date, t.date), $0.id) < (dayGap($1.date, t.date), $1.id) }
        }
        func nearestIsUnique(_ list: [Transaction], to t: Transaction) -> Bool {
            list.count < 2 || dayGap(list[0].date, t.date) != dayGap(list[1].date, t.date)
        }
        for id in newIDs {
            guard let t = all[id], t.transferPairID == nil else { continue }
            let mine = partners(of: t)
            guard let best = mine.first else { continue }
            // Both sides must agree: neither may have two equally close candidates.
            guard nearestIsUnique(mine, to: t), nearestIsUnique(partners(of: best), to: best) else {
                let label = "\(Money.format(abs(t.amount))) around \(t.date): more than one possible match for a card payment"
                if !report.ambiguousTransfers.contains(label) { report.ambiguousTransfers.append(label) }
                continue
            }
            var a = t, b = best
            a.transferPairID = b.id; b.transferPairID = a.id
            a.categoryID = nil; b.categoryID = nil
            put(a); put(b)
            report.linkedTransfers += 1
        }

        for sf in response.accounts {
            guard let account = bySF[sf.id], let bank = SimpleFIN.parseAmount(sf.balance) else { continue }
            let ours = all.values.filter { $0.accountID == account.id }.reduce(Milliunits(0)) { $0 + $1.amount }
            report.balances.append(.init(account: account.name, simplefin: bank, coinbox: ours))
        }
        return (touched.compactMap { all[$0] }.map { Op.putTransaction($0) }, report)
    }

    /// Fetches, imports as `bank`, then runs the rules over what just arrived (also as `bank`). Meant for the hub.
    public func runSimpleFINSync(fetcher: SimpleFINFetcher, days: Int = 30, timeZone: TimeZone = .current) async throws -> SimpleFINReport {
        let data = try await fetcher.fetch(since: Date().addingTimeInterval(-Double(days) * 86_400))
        guard let response = try? JSONDecoder().decode(SFResponse.self, from: data) else { throw CoinboxError.invalid("SimpleFIN answered with something unreadable") }
        var (ops, report) = try planSimpleFINImport(response, timeZone: timeZone)
        let before = Set(try transactions().map(\.id))
        var i = 0
        while i < ops.count { try perform(Array(ops[i..<min(i + 200, ops.count)]), author: .bank); i += 200 }
        ops.removeAll()
        let arrived = try transactions().filter { !$0.approved && $0.bankImportID != nil && !before.contains($0.id) }.map(\.id)
        if !arrived.isEmpty {
            let batch = try planRuleApplication(ids: arrived)
            if !batch.ops.isEmpty { try perform(batch.ops, author: .bank) }
            report.rulesApplied = batch.changes.filter { $0.skipped == nil }.count
        }
        return report
    }
}
