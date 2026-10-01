import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    typealias Completion = (Result<AppleCredentials, Error>) -> Void
    private var completion: Completion?
    private weak var anchorWindow: UIWindow?

    func start(anchor: UIWindow?, completion: @escaping Completion) {
        self.anchorWindow = anchor
        self.completion = completion
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchorWindow ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              let codeData = credential.authorizationCode,
              let code = String(data: codeData, encoding: .utf8) else {
            completion?(.failure(AppleSignInError.missingCredentials))
            completion = nil
            return
        }
        let nameParts = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }
        completion?(.success(AppleCredentials(identityToken: token, authorizationCode: code, displayName: nameParts.isEmpty ? nil : nameParts.joined(separator: " "))))
        completion = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion?(.failure(error))
        completion = nil
    }
}

struct AppleCredentials: Sendable {
    let identityToken: String
    let authorizationCode: String
    let displayName: String?
}

enum AppleSignInError: LocalizedError {
    case missingCredentials
    var errorDescription: String? { "Apple did not return the credentials needed to create a revocable account." }
}
