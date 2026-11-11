import Foundation

public enum TextMode: String, Codable, Sendable { case contains, equals, regex }

public struct TextMatch: Codable, Sendable, Equatable {
    public var mode: TextMode
    public var text: String
    public init(_ mode: TextMode, _ text: String) { self.mode = mode; self.text = text }
}

/// JSON: {"type": "equals", "amount": -4500}, {"type": "range", "min": -50000, "max": 0}, {"type": "endsWithCents", "cents": 99}.
public enum AmountMatch: Codable, Sendable, Equatable {
    case equals(Milliunits)
    /// Inclusive, on the signed amount.
    case range(min: Milliunits, max: Milliunits)
    /// The cents of the absolute amount, 0...99.
    case endsWithCents(Int)

    private enum Keys: String, CodingKey { case type, amount, min, max, cents }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "equals": self = .equals(try c.decode(Milliunits.self, forKey: .amount))
        case "range": self = .range(min: try c.decode(Milliunits.self, forKey: .min), max: try c.decode(Milliunits.self, forKey: .max))
        case "endsWithCents": self = .endsWithCents(try c.decode(Int.self, forKey: .cents))
        case let other: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown amount match \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .equals(a): try c.encode("equals", forKey: .type); try c.encode(a, forKey: .amount)
        case let .range(lo, hi): try c.encode("range", forKey: .type); try c.encode(lo, forKey: .min); try c.encode(hi, forKey: .max)
        case let .endsWithCents(n): try c.encode("endsWithCents", forKey: .type); try c.encode(n, forKey: .cents)
        }
    }
}

public struct RuleActions: Codable, Sendable, Equatable {
    public var renamePayee: String?
    public var categoryID: String?
    public var memo: String?
    public var approve: Bool

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.init(renamePayee: try c.decodeIfPresent(String.self, forKey: .renamePayee), categoryID: try c.decodeIfPresent(String.self, forKey: .categoryID),
                  memo: try c.decodeIfPresent(String.self, forKey: .memo), approve: try c.decodeIfPresent(Bool.self, forKey: .approve) ?? false)
    }

    public init(renamePayee: String? = nil, categoryID: String? = nil, memo: String? = nil, approve: Bool = false) {
        self.renamePayee = renamePayee; self.categoryID = categoryID; self.memo = memo; self.approve = approve
    }
}

/// An ordered import rule. Every condition that is present must match; the first matching rule in list order wins.
public struct Rule: Codable, Sendable, Equatable {
    public var id: String
    public var order: Int
    public var name: String
    public var payee: TextMatch?
    public var amount: AmountMatch?
    public var accountIDs: [String]
    public var memo: TextMatch?
    public var actions: RuleActions

    public init(id: String = UUID().uuidString.lowercased(), order: Int = 0, name: String, payee: TextMatch? = nil, amount: AmountMatch? = nil,
                accountIDs: [String] = [], memo: TextMatch? = nil, actions: RuleActions) {
        self.id = id; self.order = order; self.name = name; self.payee = payee; self.amount = amount; self.accountIDs = accountIDs; self.memo = memo; self.actions = actions
    }

    /// Lenient: only `name` and `actions` are required.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased(), order: try c.decodeIfPresent(Int.self, forKey: .order) ?? 0,
                  name: try c.decode(String.self, forKey: .name), payee: try c.decodeIfPresent(TextMatch.self, forKey: .payee),
                  amount: try c.decodeIfPresent(AmountMatch.self, forKey: .amount), accountIDs: try c.decodeIfPresent([String].self, forKey: .accountIDs) ?? [],
                  memo: try c.decodeIfPresent(TextMatch.self, forKey: .memo), actions: try c.decode(RuleActions.self, forKey: .actions))
    }
}
