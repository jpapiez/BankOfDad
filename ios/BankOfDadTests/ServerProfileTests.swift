import XCTest
@testable import BankOfDad

final class ServerProfileTests: XCTestCase {
    func testHTTPSPublicOriginIsAcceptedAndNormalized() throws {
        XCTAssertEqual(
            try ServerOriginPolicy.validate("https://family.example").absoluteString,
            "https://family.example"
        )
        XCTAssertThrowsError(try ServerOriginPolicy.validate("https://user@family.example"))
        XCTAssertThrowsError(try ServerOriginPolicy.validate("https://family.example/api"))
    }

    func testHTTPIsLimitedToPrivateHosts() throws {
        let allowed = [
            "http://localhost:8080",
            "http://bank.local",
            "http://10.0.0.2",
            "http://172.16.0.2",
            "http://172.31.255.254",
            "http://192.168.1.2",
            "http://[::1]",
            "http://[fd00::1]"
        ]
        for value in allowed {
            XCTAssertNoThrow(try ServerOriginPolicy.validate(value), value)
        }
        XCTAssertThrowsError(try ServerOriginPolicy.validate("http://family.example"))
        XCTAssertThrowsError(try ServerOriginPolicy.validate("http://172.32.0.1"))
        XCTAssertThrowsError(try ServerOriginPolicy.validate("ftp://192.168.1.2"))
    }

    func testConnectionLinkParsesVersionedServerBoundEnrollment() throws {
        let serverID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        var components = URLComponents(string: "bankofdad://connect")!
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "origin", value: "https://family.example"),
            URLQueryItem(name: "server", value: serverID.uuidString),
            URLQueryItem(name: "kind", value: "child"),
            URLQueryItem(name: "token", value: String(repeating: "a", count: 43))
        ]

        let link = try ServerConnectionLink(scannedValue: components.url!.absoluteString)

        XCTAssertEqual(link.origin.absoluteString, "https://family.example")
        XCTAssertEqual(link.serverID, serverID)
        XCTAssertEqual(link.kind, .child)
        XCTAssertEqual(link.token, String(repeating: "a", count: 43))
    }

    func testConnectionLinkRejectsOldPairingAndUnsafeOrigin() {
        XCTAssertThrowsError(try ServerConnectionLink(scannedValue: "bankofdad://pair?code=ABC123"))
        XCTAssertThrowsError(
            try ServerConnectionLink(
                scannedValue: "bankofdad://connect?v=1&origin=http%3A%2F%2Fpublic.example&server=11111111-1111-4111-8111-111111111111&kind=parent&token=\(String(repeating: "a", count: 43))"
            )
        )
    }

    func testProfileUsesOnlyVerifiedDescriptorValues() throws {
        let descriptor = ServerDescriptor(
            protocolVersion: 1,
            serverId: UUID(),
            origin: "https://family.example",
            setupState: "ready",
            familyName: "Example Family",
            capabilities: ServerCapabilities(parentPassword: true, childPassword: true, childPin: true, apple: false, push: false),
            childPin: ChildPinPolicy(minimumLength: 7, maximumLength: 12)
        )

        let profile = try ServerProfile(descriptor: descriptor)

        XCTAssertEqual(profile.id, descriptor.serverId)
        XCTAssertEqual(profile.familyName, "Example Family")
        XCTAssertEqual(profile.childPin.minimumLength, 7)
        XCTAssertFalse(profile.capabilities.apple)
        XCTAssertFalse(profile.capabilities.push)
    }
}
