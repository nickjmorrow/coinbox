import Foundation

/// Fetches one YNAB API path (relative to /budgets/{plan}/) and returns the response body.
public protocol YNABFetcher: Sendable {
    func get(_ path: String) async throws -> Data
}

/// Talks to api.ynab.com with a personal access token. Read only: it only ever issues GETs.
public struct HTTPYNABFetcher: YNABFetcher {
    let token: String
    let planID: String
    let session: URLSession

    public init(token: String, planID: String, session: URLSession = .shared) { self.token = token; self.planID = planID; self.session = session }

    public func get(_ path: String) async throws -> Data {
        guard let url = URL(string: "https://api.ynab.com/v1/budgets/\(planID)/\(path)") else { throw CoinboxError.invalid("bad YNAB path") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { ($0["error"] as? [String: Any])?["detail"] as? String }
            throw CoinboxError.invalid("YNAB said \(status)" + (detail.map { ": \($0)" } ?? ""))
        }
        return data
    }
}

/// Reads saved API responses from a folder: accounts.json, categories.json, payees.json, months.json, month-YYYY-MM-DD.json, transactions.json.
public struct DirectoryYNABFetcher: YNABFetcher {
    let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func get(_ path: String) async throws -> Data {
        let name: String
        if path.hasPrefix("months/") { name = "month-" + path.dropFirst(7) } else { name = String(path.split(separator: "?")[0]) }
        let file = directory.appendingPathComponent(name + ".json")
        guard let data = try? Data(contentsOf: file) else { throw CoinboxError.notFound("saved YNAB response \(file.lastPathComponent)") }
        return data
    }
}

public struct YNABSource: Sendable {
    let fetcher: YNABFetcher
    public init(_ fetcher: YNABFetcher) { self.fetcher = fetcher }

    private struct Wrapper<T: Decodable>: Decodable { var data: T }
    private struct Accounts: Decodable { var accounts: [YNABAccount] }
    private struct Payees: Decodable { var payees: [YNABPayee] }
    private struct Groups: Decodable { var categoryGroups: [YNABGroup] }
    private struct Months: Decodable { var months: [YNABMonth] }
    private struct OneMonth: Decodable { var month: YNABMonth }
    private struct Transactions: Decodable { var transactions: [YNABTransaction] }

    private func decode<T: Decodable>(_ type: T.Type, _ path: String) async throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(Wrapper<T>.self, from: try await fetcher.get(path)).data }
        catch let e as CoinboxError { throw e }
        catch { throw CoinboxError.invalid("couldn't read YNAB's answer for \(path): \(error)") }
    }

    /// Everything from `since` (a date, "2026-01-01") onward, plus the structure around it.
    public func snapshot(since: String) async throws -> YNABSnapshot {
        let accounts = try await decode(Accounts.self, "accounts").accounts
        let payees = try await decode(Payees.self, "payees").payees
        let groups = try await decode(Groups.self, "categories").categoryGroups
        let listed = try await decode(Months.self, "months").months.filter { $0.month >= String(since.prefix(7)) + "-01" }
        var months: [YNABMonth] = []
        for m in listed.sorted(by: { $0.month < $1.month }) { months.append(try await decode(OneMonth.self, "months/\(m.month)").month) }
        let transactions = try await decode(Transactions.self, "transactions?since_date=\(since)").transactions
        return YNABSnapshot(accounts: accounts, payees: payees, groups: groups, months: months, transactions: transactions)
    }
}
