import Foundation
import Testing
@testable import CoinboxCore

/// Answers from a canned table and remembers what it was asked.
private final class Canned: CategorizerModel, @unchecked Sendable {
    var answers: [String: (String, String)]
    var prompts: [String] = []
    init(_ answers: [String: (String, String)]) { self.answers = answers }
    func complete(system: String, user: String, schema: [String: Any]) async throws -> Data {
        prompts.append(user)
        let results = answers.map { "{\"id\":\"\($0.key)\",\"category\":\"\($0.value.0)\",\"confidence\":\"\($0.value.1)\"}" }
        return Data("{\"results\":[\(results.joined(separator: ","))]}".utf8)
    }
}

@Suite struct AICategorizerTests {
    private func setup() throws -> Fixture {
        let f = try Fixture()
        try f.account("chk"); try f.category("groc"); try f.category("fun")
        try f.c.perform([.putPayee(Payee(id: "p", name: "Trader Joe's")),
                         .putTransaction(Transaction(id: "old", accountID: "chk", date: "2026-01-02", payeeID: "p", categoryID: "groc", amount: -20_000, approved: true))], author: .mac)
        for (id, raw) in [("a", "TRADER JOE'S #1"), ("b", "MYSTERY LLC"), ("c", "SOMEWHERE")] {
            try f.c.perform([.putTransaction(Transaction(id: id, accountID: "chk", date: "2026-01-05", payeeID: id == "a" ? "p" : nil, amount: -5_000, approved: false, rawPayee: raw, author: .bank))], author: .bank)
        }
        return f
    }

    @Test func categorizesConfidentOnesAndLeavesTheRest() async throws {
        let f = try setup()
        let model = Canned(["a": ("groc", "high"), "b": ("fun", "low"), "c": ("none", "low")])
        let plan = try await f.c.planAICategorization(model: model)
        let done = plan.changes.filter { $0.skipped == nil }
        #expect(done.count == 1 && done[0].transactionID == "a" && done[0].categoryAfter == "groc" && !done[0].approvedAfter && done[0].source == "ai high")
        #expect(plan.changes.filter { $0.skipped != nil }.count == 2)
        #expect(model.prompts.count == 1 && model.prompts[0].contains("Trader Joe's") && model.prompts[0].contains("Spending > groc"))   // history reaches the model
        #expect(try f.c.transaction(id: "a")?.categoryID == nil)                                                                      // planning wrote nothing
    }

    @Test func approveOnlyWhereHighAndMinConfidenceHolds() async throws {
        let f = try setup()
        let model = Canned(["a": ("groc", "high"), "b": ("fun", "medium"), "c": ("fun", "low")])
        let plan = try await f.c.planAICategorization(model: model, options: AICategorizeOptions(approve: true))
        let byID = Dictionary(plan.changes.map { ($0.transactionID, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byID["a"]?.approvedAfter == true && byID["b"]?.categoryAfter == "fun" && byID["b"]?.approvedAfter == false && byID["c"]?.skipped != nil)
    }

    @Test func invalidCategoryAndMissingAnswerAreSkippedNotApplied() async throws {
        let f = try setup()
        let plan = try await f.c.planAICategorization(model: Canned(["a": ("not-a-category", "high")]))
        #expect(plan.changes.allSatisfy { $0.skipped != nil } && plan.ops.isEmpty)
    }

    @Test func batchesAndSkipsTransfersAndSplits() async throws {
        let f = try setup()
        let model = Canned([:])
        _ = try await f.c.planAICategorization(model: model, options: AICategorizeOptions(batchSize: 2))
        #expect(model.prompts.count == 2)       // a, b, c in batches of 2
    }
}
