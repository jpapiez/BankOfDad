import XCTest
@testable import BankOfDad

final class APIClientTests: XCTestCase {
    func testBuildRequestAddsBearerHeader() async throws {
        let vault = TokenVault()
        await vault.update(accessToken: "access", refreshToken: "refresh")
        let client = APIClient(baseURL: URL(string: "http://localhost:8080")!, vault: vault)
        let request = try await client.buildRequest(for: APIEndpoint<UserDto>(method: "GET", path: "/auth/me"))
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8080/api/v1/auth/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
    }

    func testRefreshAfter401RetriesOnce() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let vault = TokenVault()
        await vault.update(accessToken: "old", refreshToken: "refresh")
        let client = APIClient(baseURL: URL(string: "http://localhost:8080")!, vault: vault, urlSession: session)
        var loanRequestCount = 0
        StubURLProtocol.handler = { request in
            if request.url?.path == "/api/v1/auth/refresh" {
                let body = #"{ "accessToken": "new", "refreshToken": "new-refresh", "expiresAt": "2026-09-27T22:15:00Z", "user": { "id": "00000000-0000-0000-0000-000000000001", "familyId": "00000000-0000-0000-0000-000000000002", "role": "parent", "displayName": "Dad", "email": "dad@example.com" } }"#
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data(body.utf8))
            }
            if request.url?.path == "/api/v1/loans" {
                loanRequestCount += 1
                if loanRequestCount == 1 {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old")
                    return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: ["Content-Type": "application/problem+json"])!, Data(#"{ "title": "Unauthorized", "status": 401 }"#.utf8))
                }
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data("[]".utf8))
            }
            XCTFail("Unexpected request: \(request.url?.absoluteString ?? "nil")")
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        let loans: [LoanSummary] = try await client.get("/loans")
        XCTAssertTrue(loans.isEmpty)
        XCTAssertEqual(loanRequestCount, 2)
        let access = await vault.tokens().access
        XCTAssertEqual(access, "new")
    }
}

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
