import Foundation

public enum Author: String, Codable, Sendable { case mac, iphone, claude, bank, importer = "import" }

/// A free-text note on one calendar month, keyed "YYYY-MM".
public struct MonthNote: Codable, Sendable, Equatable {
    public var month: String
    public var text: String

    public init(month: String, text: String) { self.month = month; self.text = text }
}
