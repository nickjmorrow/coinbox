import ArgumentParser
import CoinboxCore
import Foundation

struct RunResult {
    var code: Int32
    var out: String
    var err: String
}

final class OutputBuffer: @unchecked Sendable {
    var text = ""
}

enum Output {
    /// Each invocation of `Runner.run` gets its own buffer, so concurrent runs (tests) never mix their output.
    @TaskLocal static var current = OutputBuffer()

    static func json<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        current.text += String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
    }
}

/// Parses and runs one invocation; success prints JSON to out, failure prints {"error": ...} to err with code 1.
enum Runner {
    static func run(_ args: [String]) async -> RunResult {
        let buffer = OutputBuffer()
        return await Output.$current.withValue(buffer) { await execute(args, buffer) }
    }

    private static func execute(_ args: [String], _ buffer: OutputBuffer) async -> RunResult {
        var command: ParsableCommand
        do {
            command = try CoinboxCommand.parseAsRoot(args)
        } catch {
            let code = CoinboxCommand.exitCode(for: error).rawValue
            let message = CoinboxCommand.fullMessage(for: error) + "\n"
            return code == 0 ? RunResult(code: 0, out: message, err: "") : RunResult(code: code, out: "", err: message)
        }
        do {
            if var async = command as? AsyncParsableCommand { try await async.run() } else { try command.run() }
            return RunResult(code: 0, out: buffer.text, err: "")
        } catch {
            // Asking for help on a command group reaches here as an error that means "success".
            if !(error is CoinboxError), CoinboxCommand.exitCode(for: error) == .success { return RunResult(code: 0, out: CoinboxCommand.fullMessage(for: error) + "\n", err: "") }
            let message = (error as? CoinboxError)?.message ?? "\(error)"
            let data = (try? JSONSerialization.data(withJSONObject: ["error": message], options: [.sortedKeys])) ?? Data()
            return RunResult(code: 1, out: "", err: String(decoding: data, as: UTF8.self) + "\n")
        }
    }
}

struct GlobalOptions: ParsableArguments {
    @Option(help: "Database file. Defaults to $COINBOX_DB, else ~/Library/Application Support/Coinbox/coinbox.sqlite.")
    var db: String?

    @Option(help: "Who is making the change: mac, iphone, claude, bank or import.")
    var author: Author = .claude

    var databasePath: String {
        db ?? ProcessInfo.processInfo.environment["COINBOX_DB"] ?? (NSHomeDirectory() + "/Library/Application Support/Coinbox/coinbox.sqlite")
    }

    func open() throws -> Coinbox {
        try Coinbox.open(path: databasePath, device: "dev-" + String(UUID().uuidString.prefix(8)).lowercased())
    }
}

extension Author: @retroactive ExpressibleByArgument {}
