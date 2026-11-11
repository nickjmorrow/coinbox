import Foundation

/// Asks a language model one question and returns its answer text (JSON). Swappable so tests never touch the network.
public protocol CategorizerModel: Sendable {
    func complete(system: String, user: String, schema: [String: Any]) async throws -> Data
}

/// Talks to api.anthropic.com Messages with an API key. The key is never put in an error.
public struct AnthropicModel: CategorizerModel, @unchecked Sendable {
    let apiKey: String
    let model: String
    let session: URLSession

    public init(apiKey: String, model: String = "claude-haiku-5-5", session: URLSession = .shared) { self.apiKey = apiKey; self.model = model; self.session = session }

    public func complete(system: String, user: String, schema: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model, "max_tokens": 8000, "system": system,
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "messages": [["role": "user", "content": user]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
            let detail = (json?["error"] as? [String: Any])?["message"] as? String
            throw CoinboxError.invalid("Anthropic said \(status)" + (detail.map { ": \($0)" } ?? ""))
        }
        let text = (json?["content"] as? [[String: Any]])?.first { $0["type"] as? String == "text" }?["text"] as? String
        guard let text, let out = text.data(using: .utf8) else { throw CoinboxError.invalid("Anthropic returned no text (stop reason: \(json?["stop_reason"] as? String ?? "unknown"))") }
        return out
    }
}

public struct AICategorizeOptions: Sendable {
    public var ids: [String]?
    public var includeCategorized = false
    public var approve = false
    public var minConfidence = "medium"
    public var batchSize = 25
    public init(ids: [String]? = nil, includeCategorized: Bool = false, approve: Bool = false, minConfidence: String = "medium", batchSize: Int = 25) {
        self.ids = ids; self.includeCategorized = includeCategorized; self.approve = approve; self.minConfidence = minConfidence; self.batchSize = batchSize
    }
}

enum AICategorizer {
    static var schema: [String: Any] { [
        "type": "object", "additionalProperties": false, "required": ["results"],
        "properties": ["results": ["type": "array", "items": [
            "type": "object", "additionalProperties": false, "required": ["id", "category", "confidence"],
            "properties": ["id": ["type": "string"], "category": ["type": "string"], "confidence": ["type": "string", "enum": ["high", "medium", "low"]]],
        ]]],
    ] }

    static let system = """
    You categorize bank transactions for one person's budget. For each transaction pick exactly one category id from the list.
    Use the transaction's history (how the same payee was categorized before) as the strongest evidence; then the payee text, amount and account.
    Answer "none" as the category when you cannot tell: never guess to be helpful. Confidence is "high" only when the history or the payee makes it obvious,
    "medium" when it is a sensible best fit, "low" otherwise. A positive amount is money coming in; use the Ready to Assign category only for income.
    """

    static func rank(_ c: String) -> Int { ["low": 0, "medium": 1, "high": 2][c] ?? -1 }
    static func dollars(_ m: Milliunits) -> String { String(format: "%.2f", Double(m) / 1000) }
}

extension Coinbox {
    /// Plans categories for unapproved, unsplit, non-transfer transactions that have none (or all of them with `includeCategorized`).
    /// Each batch goes to the model with the category list and, per transaction, up to three earlier approved transactions of the same payee.
    /// Categorizes only; approves only with `approve` and only where the model said "high". Plans only: nothing is written.
    public func planAICategorization(model: CategorizerModel, options: AICategorizeOptions = AICategorizeOptions()) async throws -> PlannedBatch {
        let b = try BatchPlanner(self)
        let categoryNames: [String: String] = {
            let groups = (try? categoryGroups()) ?? []
            let groupName = Dictionary(groups.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            return Dictionary(b.categories.values.map { ($0.id, ($0.kind == .readyToAssign ? "Inflow" : (groupName[$0.groupID] ?? "")) + " > " + $0.name) }, uniquingKeysWith: { a, _ in a })
        }()
        let choices = b.categories.values.filter { !$0.hidden && ($0.kind == .normal || $0.kind == .readyToAssign) }.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
        let catalog = choices.map { "\($0.id) | \(categoryNames[$0.id] ?? $0.name)" }.joined(separator: "\n")

        func payeeKey(_ t: Transaction) -> String? {
            (t.payeeID.flatMap { b.payees[$0]?.name } ?? t.rawPayee)?.lowercased()
        }
        var history: [String: [Transaction]] = [:]
        for t in b.allTransactions.sorted(by: { ($0.date, $0.id) > ($1.date, $1.id) }) where t.approved && t.categoryID != nil && t.splits.isEmpty {
            if let k = payeeKey(t), history[k, default: []].count < 3 { history[k, default: []].append(t) }
        }

        let ids = options.ids ?? b.original.values.map(\.id)
        var targets: [Transaction] = []
        for id in ids.sorted() {
            guard let t = b.original[id] else { b.skip(id, "not found"); continue }
            guard !t.approved || options.ids != nil, t.splits.isEmpty, t.transferPairID == nil, !t.pending else { continue }
            guard options.includeCategorized || t.categoryID == nil else { continue }
            targets.append(t)
        }
        targets.sort { ($0.date, $0.id) < ($1.date, $1.id) }

        let valid = Set(choices.map(\.id))
        let need = AICategorizer.rank(options.minConfidence)
        var start = 0
        while start < targets.count {
            let slice = Array(targets[start..<min(start + options.batchSize, targets.count)])
            start += options.batchSize
            let rows: [[String: Any]] = slice.map { t in
                var row: [String: Any] = ["id": t.id, "date": t.date, "amount": AICategorizer.dollars(t.amount), "account": b.accounts[t.accountID]?.name ?? ""]
                row["payee"] = t.payeeID.flatMap { b.payees[$0]?.name } ?? t.rawPayee ?? ""
                if let raw = t.rawPayee { row["bank_text"] = raw }
                if let memo = t.memo, !memo.isEmpty { row["memo"] = memo }
                row["history"] = (payeeKey(t).flatMap { history[$0] } ?? []).map { ["amount": AICategorizer.dollars($0.amount), "category": categoryNames[$0.categoryID ?? ""] ?? ""] }
                return row
            }
            let user = "Categories (id | group > name):\n\(catalog)\n\nTransactions:\n" + String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), as: UTF8.self)
            let data = try await model.complete(system: AICategorizer.system, user: user, schema: AICategorizer.schema)
            struct Answer: Decodable { struct R: Decodable { var id: String; var category: String; var confidence: String }; var results: [R] }
            let answer = try JSONDecoder().decode(Answer.self, from: data)
            let byID = Dictionary(answer.results.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for t in slice {
                guard let r = byID[t.id] else { b.skip(t.id, "the model gave no answer"); continue }
                guard valid.contains(r.category) else { b.skip(t.id, "the model wasn't sure"); continue }
                guard AICategorizer.rank(r.confidence) >= need else { b.skip(t.id, "low confidence (\(r.confidence)): \(categoryNames[r.category] ?? r.category)"); continue }
                b.categorize(t.id, to: r.category, source: "ai \(r.confidence)")
                if options.approve, r.confidence == "high", b.skipped[t.id] == nil { b.approve(t.id, source: "ai high") }
            }
        }
        return b.finish()
    }
}

#if os(macOS)
/// Runs the `claude` CLI in print mode (uses the user's own Claude login, so no API key). Tools, settings, skills and MCP servers are
/// all switched off so each call carries only our prompt.
public struct ClaudeCLIModel: CategorizerModel {
    let model: String
    let executable: String

    public init(model: String = "claude-haiku-5-5", executable: String = "claude") { self.model = model; self.executable = executable }

    public func complete(system: String, user: String, schema: [String: Any]) async throws -> Data {
        let schemaText = String(decoding: try JSONSerialization.data(withJSONObject: schema), as: UTF8.self)
        let args = ["-p", "--model", model, "--output-format", "json", "--tools", "", "--setting-sources", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
                    "--disable-slash-commands", "--no-session-persistence", "--system-prompt", system, "--json-schema", schemaText]
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let p = Process(), inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                p.arguments = [executable] + args
                p.currentDirectoryURL = FileManager.default.temporaryDirectory      // keep project instruction files out of it
                p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
                do { try p.run() } catch { cont.resume(throwing: CoinboxError.invalid("couldn't start \(executable): \(error.localizedDescription)")); return }
                DispatchQueue.global().async { inPipe.fileHandleForWriting.write(Data(user.utf8)); try? inPipe.fileHandleForWriting.close() }
                var err = Data()
                let errDone = DispatchSemaphore(value: 0)
                DispatchQueue.global().async { err = errPipe.fileHandleForReading.readDataToEndOfFile(); errDone.signal() }
                let out = outPipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit(); errDone.wait()
                guard p.terminationStatus == 0 else {
                    cont.resume(throwing: CoinboxError.invalid("claude exited \(p.terminationStatus): " + String(decoding: err.prefix(300), as: UTF8.self))); return
                }
                let json = (try? JSONSerialization.jsonObject(with: out)) as? [String: Any]
                if json?["is_error"] as? Bool == true { cont.resume(throwing: CoinboxError.invalid("claude: \(json?["result"] as? String ?? "error")")); return }
                if let s = json?["structured_output"], let data = try? JSONSerialization.data(withJSONObject: s) { cont.resume(returning: data); return }
                if let text = json?["result"] as? String { cont.resume(returning: Data(text.utf8)); return }
                cont.resume(throwing: CoinboxError.invalid("claude returned nothing usable"))
            }
        }
    }
}
#endif
