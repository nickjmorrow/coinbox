import ArgumentParser
import CoinboxCore
import Foundation

struct AICategorize: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ai-categorize",
        abstract: "Have a small model (Haiku) categorize unapproved transactions from how the same payees were categorized before. --preview writes nothing.")
    @OptionGroup var global: GlobalOptions
    @Option(help: "Comma-separated transaction ids; default every unapproved, uncategorized, non-transfer transaction.") var ids: String?
    @Flag(name: .customLong("include-categorized"), help: "Also re-suggest unapproved transactions that already have a category.") var includeCategorized = false
    @Flag(help: "Also approve the ones the model is highly confident about.") var approve = false
    @Option(name: .customLong("min-confidence"), help: "low, medium or high: the least confidence to apply.") var minConfidence = "medium"
    @Option(help: "Model id.") var model = "claude-haiku-5-5"
    @Flag(help: "Call the Anthropic API with a key (file or ANTHROPIC_API_KEY) instead of the claude CLI.") var api = false
    @Option(name: .customLong("key-file"), help: "With --api: file holding the key.") var keyFile = "~/.config/coinbox/anthropic_key"
    @Flag var preview = false

    func run() async throws {
        guard ["low", "medium", "high"].contains(minConfidence) else { throw CoinboxError.invalid("--min-confidence is low, medium or high") }
        let llm: CategorizerModel
        if api {
            let path = (keyFile as NSString).expandingTildeInPath
            let fromFile = (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let key = [ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], fromFile].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
                throw CoinboxError.invalid("no Anthropic API key: put it in \(path) (mode 600) or set ANTHROPIC_API_KEY")
            }
            llm = AnthropicModel(apiKey: key, model: model)
        } else {
            llm = ClaudeCLIModel(model: model)
        }
        let c = try global.open()
        let list = ids.map { $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } }
        let options = AICategorizeOptions(ids: list, includeCategorized: includeCategorized, approve: approve, minConfidence: minConfidence)
        let plan = try await c.planAICategorization(model: llm, options: options)
        try finish(plan, preview: preview, coinbox: c, author: global.author)
    }
}
