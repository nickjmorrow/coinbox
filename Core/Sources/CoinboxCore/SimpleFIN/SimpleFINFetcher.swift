import Foundation

public protocol SimpleFINFetcher: Sendable {
    /// The raw `/accounts` response for activity since `since`.
    func fetch(since: Date) async throws -> Data
}

/// Talks to the SimpleFIN Bridge with the access URL (`https://user:pass@host/simplefin`). The URL is a secret: it is only read
/// from a file by the caller, and every error text goes through `SimpleFIN.redact`.
public struct HTTPSimpleFINFetcher: SimpleFINFetcher {
    private let base: URL
    private let authorization: String
    let session: URLSession

    public init(accessURL: String, session: URLSession = .shared) throws {
        let trimmed = accessURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: trimmed), let user = comps.user, let password = comps.password, comps.host != nil else {
            throw CoinboxError.invalid("the SimpleFIN access URL should look like https://user:password@host/simplefin")
        }
        comps.user = nil; comps.password = nil
        guard let url = comps.url else { throw CoinboxError.invalid("the SimpleFIN access URL isn't valid") }
        base = url
        authorization = "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
        self.session = session
    }

    public func fetch(since: Date) async throws -> Data {
        var comps = URLComponents(url: base.appendingPathComponent("accounts"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "start-date", value: String(Int(since.timeIntervalSince1970))), URLQueryItem(name: "pending", value: "1")]
        var request = URLRequest(url: comps.url!)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw CoinboxError.invalid("SimpleFIN said \(status)") }
            return data
        } catch let e as CoinboxError { throw e }
        catch { throw CoinboxError.invalid("couldn't reach SimpleFIN: " + SimpleFIN.redact("\(error.localizedDescription)")) }
    }
}

/// Reads a saved `/accounts` response (for tests and offline runs).
public struct FileSimpleFINFetcher: SimpleFINFetcher {
    let url: URL
    public init(url: URL) { self.url = url }
    public func fetch(since: Date) async throws -> Data {
        guard let data = try? Data(contentsOf: url) else { throw CoinboxError.notFound("saved SimpleFIN response \(url.lastPathComponent)") }
        return data
    }
}

extension SimpleFIN {
    /// Trades a one-time setup token (base64 of a claim URL) for the access URL. Returns the access URL: the caller must store it
    /// in a private file and never print it.
    public static func claim(setupToken: String, session: URLSession = .shared) async throws -> String {
        let cleaned = setupToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: cleaned) ?? Data(base64Encoded: cleaned + String(repeating: "=", count: (4 - cleaned.count % 4) % 4)),
              let claimString = String(data: data, encoding: .utf8), let claimURL = URL(string: claimString), claimURL.scheme?.hasPrefix("http") == true else {
            throw CoinboxError.invalid("that doesn't look like a SimpleFIN setup token")
        }
        var request = URLRequest(url: claimURL)
        request.httpMethod = "POST"
        do {
            let (body, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let access = String(data: body, encoding: .utf8), access.hasPrefix("http") else {
                throw CoinboxError.invalid("SimpleFIN said \(status); a setup token only works once")
            }
            return access.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let e as CoinboxError { throw e }
        catch { throw CoinboxError.invalid("couldn't reach SimpleFIN: " + redact("\(error.localizedDescription)")) }
    }
}
