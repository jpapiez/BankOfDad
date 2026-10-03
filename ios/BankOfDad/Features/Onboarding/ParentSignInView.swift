import SwiftUI

@MainActor
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
                    .accessibilityIdentifier("signIn.email")
                SecureField("Password", text: $password)
                    .textContentType(isRegistering ? .newPassword : .password)
                    .accessibilityIdentifier("signIn.password")
                if isRegistering || isAcceptingInvite {
                    TextField("Your name", text: $displayName).textContentType(.name)
                        .accessibilityIdentifier("signIn.displayName")
                }
                if isRegistering {
                    TextField("Family name", text: $familyName)
                        .accessibilityIdentifier("signIn.familyName")
                }
                if isAcceptingInvite {
                    TextField("Invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: inviteCode) { _, newValue in inviteCode = PairingCode.display(newValue) }
                        .accessibilityIdentifier("signIn.inviteCode")
                }
                Button(primaryTitle) { submit() }
                    .disabled(!canSubmit || authSession.isAuthenticating)
                    .accessibilityIdentifier("signIn.submit")
                if authSession.isAuthenticating { ProgressView() }
            }

            Section {
                Button(isRegistering ? "I already have an account" : "Create a parent account") {
                    isRegistering.toggle(); isAcceptingInvite = false
                }
                .accessibilityIdentifier("signIn.toggleRegister")
                Button(isAcceptingInvite ? "Use regular sign in" : "Join with invite code") {
                    isAcceptingInvite.toggle(); isRegistering = false
                }
                .accessibilityIdentifier("signIn.toggleInvite")
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
}
