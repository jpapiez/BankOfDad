import AuthenticationServices
import SwiftUI

struct ParentSignInView: View {
    @Environment(AuthSession.self) private var authSession
    @State private var isRegistering = false
    @State private var isAcceptingInvite = false
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var familyName = ""
    @State private var inviteCode = ""

    var body: some View {
        Form {
            if let error = authSession.errorMessage { ErrorBanner(message: error) }
            Section(isAcceptingInvite ? "Join a family" : (isRegistering ? "Create your family bank" : "Sign in")) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                SecureField("Password", text: $password)
                    .textContentType(isRegistering ? .newPassword : .password)
                if isRegistering || isAcceptingInvite {
                    TextField("Your name", text: $displayName).textContentType(.name)
                }
                if isRegistering {
                    TextField("Family name", text: $familyName)
                }
                if isAcceptingInvite {
                    TextField("Invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: inviteCode) { _, newValue in inviteCode = PairingCode.display(newValue) }
                }
                Button(primaryTitle) { submit() }
                    .disabled(!canSubmit || authSession.isAuthenticating)
                if authSession.isAuthenticating { ProgressView() }
            }

            Section {
                Button(isRegistering ? "I already have an account" : "Create a parent account") {
                    isRegistering.toggle(); isAcceptingInvite = false
                }
                Button(isAcceptingInvite ? "Use regular sign in" : "Join with invite code") {
                    isAcceptingInvite.toggle(); isRegistering = false
                }
            }

            Section("Sign in with Apple") {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await handleApple(result) }
                }
                .frame(height: 46)
            }
        }
        .navigationTitle("Bank access")
    }

    private var primaryTitle: String {
        if isAcceptingInvite { return "Accept invite" }
        return isRegistering ? "Create bank" : "Sign in"
    }

    private var canSubmit: Bool {
        !email.isEmpty && password.count >= 8 && (!isRegistering || (!displayName.isEmpty && !familyName.isEmpty)) && (!isAcceptingInvite || (!displayName.isEmpty && !inviteCode.isEmpty))
    }

    private func submit() {
        Task {
            if isAcceptingInvite {
                await authSession.acceptInvite(inviteCode: inviteCode, email: email, password: password, displayName: displayName)
            } else if isRegistering {
                await authSession.register(email: email, password: password, displayName: displayName, familyName: familyName, timeZone: TimeZone.current.identifier)
            } else {
                await authSession.login(email: email, password: password)
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else { return }
            let nameParts = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }
            let name = nameParts.isEmpty ? nil : nameParts.joined(separator: " ")
            await authSession.signInWithApple(identityToken: token, displayName: name, familyName: familyName.isEmpty ? nil : familyName, timeZone: TimeZone.current.identifier, inviteCode: inviteCode.isEmpty ? nil : inviteCode)
        case .failure(let error):
            authSession.errorMessage = error.localizedDescription
        }
    }
}
