import Foundation

// SimpleFIN Bridge v1 `/accounts` response. Amounts arrive as decimal strings (sometimes numbers); times as epoch seconds.

public struct SFTransaction: Codable, Sendable, Equatable {
    public var id: String
    public var posted: Int64
    public var amount: String
    public var description: String
    public var memo: String?
    public var pending: Bool

    public init(id: String, posted: Int64, amount: String, description: String, memo: String? = nil, pending: Bool = false) {
        self.id = id; self.posted = posted; self.amount = amount; self.description = description; self.memo = memo; self.pending = pending
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        posted = try SFTransaction.int(c, .posted) ?? 0
        amount = try SFTransaction.text(c, .amount) ?? "0"
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? (try c.decodeIfPresent(String.self, forKey: .payee)) ?? ""
        memo = try c.decodeIfPresent(String.self, forKey: .memo)
        pending = try c.decodeIfPresent(Bool.self, forKey: .pending) ?? false
    }

    private enum Keys: String, CodingKey { case id, posted, amount, description, payee, memo, pending }

    fileprivate static func text<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
        if let n = try? c.decodeIfPresent(Double.self, forKey: key) { return String(n) }
        return nil
    }

    fileprivate static func int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Int64? {
        if let i = try? c.decodeIfPresent(Int64.self, forKey: key) { return i }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int64(d) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int64(s) }
        return nil
    }
}

public struct SFAccount: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var currency: String
    public var balance: String
    public var orgName: String?
    public var transactions: [SFTransaction]

    public init(id: String, name: String, currency: String = "USD", balance: String = "0", orgName: String? = nil, transactions: [SFTransaction] = []) {
        self.id = id; self.name = name; self.currency = currency; self.balance = balance; self.orgName = orgName; self.transactions = transactions
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        balance = try SFTransaction.text(c, .balance) ?? "0"
        orgName = (try c.decodeIfPresent(Org.self, forKey: .org))?.name
        transactions = try c.decodeIfPresent([SFTransaction].self, forKey: .transactions) ?? []
    }

    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(currency, forKey: .currency); try c.encode(balance, forKey: .balance)
        if let orgName { try c.encode(Org(name: orgName), forKey: .org) }
        try c.encode(transactions, forKey: .transactions)
    }

    private struct Org: Codable { var name: String? }
    private enum Keys: String, CodingKey { case id, name, currency, balance, org, transactions }
}

public struct SFResponse: Codable, Sendable, Equatable {
    public var errors: [String]
    public var accounts: [SFAccount]

    public init(errors: [String] = [], accounts: [SFAccount] = []) { self.errors = errors; self.accounts = accounts }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        // `errors` is a list of strings in v1 and a list of objects with a `msg` in v2.
        if let strings = try? c.decodeIfPresent([String].self, forKey: .errors) { errors = strings }
        else if let objects = try? c.decodeIfPresent([[String: String]].self, forKey: .errors) { errors = objects.compactMap { $0["msg"] ?? $0["message"] } }
        else { errors = [] }
        accounts = try c.decodeIfPresent([SFAccount].self, forKey: .accounts) ?? []
    }
    private enum Keys: String, CodingKey { case errors, accounts }
}

public enum SimpleFIN {
    /// "12.34" → 12_340 milliunits, exactly; anything that isn't a plain decimal is nil.
    public static func parseAmount(_ s: String) -> Milliunits? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.range(of: #"^[+-]?\d+(\.\d+)?$"#, options: .regularExpression) != nil, let d = Decimal(string: t) else { return nil }
        var scaled = d * 1000, rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return Milliunits(truncating: rounded as NSNumber)
    }

    /// Hides a URL's credentials (`https://user:pass@host` → `https://host`) so errors and logs never carry the secret.
    public static func redact(_ text: String) -> String {
        text.replacingOccurrences(of: #"(https?://)[^/\s@]*@"#, with: "$1", options: .regularExpression)
    }
}
