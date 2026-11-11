import Foundation
import Testing
@testable import CoinboxCore

@Suite struct SimpleFINFetcherTests {
    private func decode(_ json: String) throws -> SFResponse { try JSONDecoder().decode(SFResponse.self, from: Data(json.utf8)) }

    @Test func decodingIsLenientAboutNumbersAndMissingFields() throws {
        let r = try decode(#"""
        {"errors":["Connection to X may need attention"],"accounts":[{"org":{"name":"Chase"},"id":"ACT-1","name":"Checking","currency":"USD","balance":"1234.50",
          "transactions":[{"id":"T1","posted":1767312000,"amount":"-12.34","description":"COFFEE"},
                          {"id":"T2","posted":1767398400.0,"amount":5,"description":"REFUND","memo":"m","pending":true}]}]}
        """#)
        #expect(r.errors == ["Connection to X may need attention"])
        #expect(r.accounts[0].orgName == "Chase" && r.accounts[0].balance == "1234.50")
        #expect(r.accounts[0].transactions[1].amount == "5.0" && r.accounts[0].transactions[1].pending && r.accounts[0].transactions[1].memo == "m")
        #expect(r.accounts[0].transactions[0].memo == nil && !r.accounts[0].transactions[0].pending)
    }

    @Test func v2StyleErrorObjectsAreRead() throws {
        #expect(try decode(#"{"errors":[{"code":"gen.auth","msg":"Needs login"}],"accounts":[]}"#).errors == ["Needs login"])
        #expect(try decode(#"{"accounts":[]}"#).errors.isEmpty)
    }

    @Test func parseAmountIsExact() {
        #expect(SimpleFIN.parseAmount("-12.34") == -12_340)
        #expect(SimpleFIN.parseAmount("0.005") == 5)
        #expect(SimpleFIN.parseAmount("100") == 100_000)
        #expect(SimpleFIN.parseAmount("1,234.5") == nil)
        #expect(SimpleFIN.parseAmount("abc") == nil)
        #expect(SimpleFIN.parseAmount("1e3") == nil)
    }

    @Test func credentialsNeverSurviveRedaction() {
        let redacted = SimpleFIN.redact("could not connect to https://alice:s3cret@bridge.example/simplefin/accounts")
        #expect(!redacted.contains("s3cret") && !redacted.contains("alice") && redacted.contains("https://bridge.example"))
    }

    @Test func badAccessURLErrorDoesNotEchoIt() {
        do { _ = try HTTPSimpleFINFetcher(accessURL: "https://alice:s3cret"); Issue.record("expected a throw") }
        catch let e as CoinboxError { #expect(!e.message.contains("s3cret")) } catch { Issue.record("wrong error") }
        #expect(throws: CoinboxError.self) { _ = try HTTPSimpleFINFetcher(accessURL: "https://no-credentials.example/simplefin") }
    }

    @Test func claimRejectsGarbageWithoutNetwork() async {
        do { _ = try await SimpleFIN.claim(setupToken: "not base64 at all!!"); Issue.record("expected a throw") }
        catch let e as CoinboxError { #expect(e.message.contains("setup token")) } catch { Issue.record("wrong error") }
    }

    @Test func fileFetcherReadsASavedResponse() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "sf-\(UUID().uuidString).json")
        try Data(#"{"accounts":[]}"#.utf8).write(to: url)
        let data = try await FileSimpleFINFetcher(url: url).fetch(since: Date())
        #expect(try JSONDecoder().decode(SFResponse.self, from: data).accounts.isEmpty)
    }
}
