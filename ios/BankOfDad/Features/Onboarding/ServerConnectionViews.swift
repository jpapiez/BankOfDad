import SwiftUI
import UIKit

@MainActor
struct ServerRequiredView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "server.rack")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.bankAccent)
                Text("Connect your family server")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Scan the setup or invitation QR shown by your family's Bank of Dad server.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ConnectServerView()
                Divider()
                NavigationLink {
                    DemoEntryView()
                } label: {
                    Label("Explore Demo Instead", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Bank of Dad")
        .background(Color(.systemGroupedBackground))
    }
}

@MainActor
struct ConnectServerView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var manualAddress = ""
    @State private var showingScanner = false
    @State private var review: ConnectionReview?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 14) {
            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }
            Button {
                showingScanner = true
            } label: {
                Label("Scan Connection QR", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("server.scan")

            HStack {
                TextField("https://family.example", text: $manualAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .accessibilityIdentifier("server.manualURL")
                Button("Connect") { discoverManualAddress() }
                    .disabled(manualAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    .accessibilityIdentifier("server.manualConnect")
            }
            if isLoading { ProgressView() }
        }
        .sheet(isPresented: $showingScanner) {
            CodeScannerView { scanned in
                showingScanner = false
                inspect(scanned)
            }
        }
        .sheet(item: $review) { review in
            ServerConfirmationView(review: review) {
                confirm(review)
            }
        }
        .task {
            if let pending = router.pendingServerConnection {
                router.pendingServerConnection = nil
                await inspect(pending)
            }
        }
        .onChange(of: router.pendingServerConnection) { _, pending in
            guard let pending else { return }
            router.pendingServerConnection = nil
            Task { await inspect(pending) }
        }
    }

    private func discoverManualAddress() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let origin = try ServerOriginPolicy.validate(manualAddress.trimmingCharacters(in: .whitespacesAndNewlines))
                let descriptor = try await ServerDiscoveryClient().discover(origin: origin)
                guard descriptor.setupState == "ready" else {
                    throw ServerConnectionError.unreachable("Open this address in a browser and use its one-time setup QR.")
                }
                review = ConnectionReview(descriptor: descriptor, link: nil, preview: nil)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func inspect(_ scanned: String) {
        Task {
            do {
                let link = try ServerConnectionLink(scannedValue: scanned)
                await inspect(link)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func inspect(_ link: ServerConnectionLink) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let (descriptor, preview) = try await ServerDiscoveryClient().inspect(link: link)
            review = ConnectionReview(descriptor: descriptor, link: link, preview: preview)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirm(_ review: ConnectionReview) {
        Task {
            do {
                let profile = try ServerProfile(descriptor: review.descriptor)
                if environment.serverProfile == nil {
                    try environment.configureServer(profile)
                } else {
                    try await environment.switchServer(to: profile)
                }
                if let link = review.link, let preview = review.preview {
                    router.pendingEnrollment = PendingEnrollment(kind: link.kind, token: link.token, preview: preview)
                }
                self.review = nil
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ConnectionReview: Identifiable {
    let descriptor: ServerDescriptor
    let link: ServerConnectionLink?
    let preview: EnrollmentPreview?
    var id: UUID { descriptor.serverId }
}

struct ServerConfirmationView: View {
    let review: ConnectionReview
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("Address", value: review.descriptor.origin)
                    LabeledContent("Family", value: review.preview?.familyName ?? review.descriptor.familyName ?? "Not created yet")
                    if let role = review.preview?.kind {
                        LabeledContent("Enrollment", value: role.label)
                    }
                    if let childName = review.preview?.childName {
                        LabeledContent("Child", value: childName)
                    }
                }
                if review.descriptor.origin.lowercased().hasPrefix("http://") {
                    Section {
                        Label("This private-network connection is not encrypted. Anyone on that network may be able to read credentials and family data.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } header: {
                        Text("Security warning")
                    }
                }
                Section("Available features") {
                    capability("Parent password", enabled: review.descriptor.capabilities.parentPassword)
                    capability("Child password", enabled: review.descriptor.capabilities.childPassword)
                    capability("Child PIN", enabled: review.descriptor.capabilities.childPin)
                    capability("Sign in with Apple", enabled: review.descriptor.capabilities.apple)
                    capability("Push notifications", enabled: review.descriptor.capabilities.push)
                }
                Button(review.descriptor.origin.lowercased().hasPrefix("http://") ? "Accept Risk and Connect" : "Connect to This Server") {
                    confirm()
                }
                .accessibilityIdentifier("server.confirm")
            }
            .navigationTitle("Confirm Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func capability(_ title: String, enabled: Bool) -> some View {
        Label(title, systemImage: enabled ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(enabled ? .primary : .secondary)
    }
}

@MainActor
struct EnrollmentDestinationView: View {
    let enrollment: PendingEnrollment
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            switch enrollment.kind {
            case .bootstrap:
                BootstrapParentView(token: enrollment.token)
            case .parent:
                ParentEnrollmentView(token: enrollment.token, suggestedEmail: enrollment.preview.email)
            case .child:
                ChildEnrollmentView(token: enrollment.token, childName: enrollment.preview.childName)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { router.pendingEnrollment = nil }
            }
        }
    }
}

@MainActor
struct BootstrapParentView: View {
    @Environment(AppEnvironment.self) private var environment
    private var authSession: AuthSession { environment.authSession }
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var familyName = ""
    let token: String

    var body: some View {
        Form {
            if let error = authSession.errorMessage { ErrorBanner(message: error) }
            Section("Create the family bank") {
                TextField("Family name", text: $familyName)
                TextField("Your name", text: $displayName).textContentType(.name)
                    .accessibilityIdentifier("enrollment.parent.name")
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .accessibilityIdentifier("enrollment.parent.email")
                SecureField("Password", text: $password).textContentType(.password)
                    .accessibilityIdentifier("enrollment.parent.password")
                Button("Create Family Bank") {
                    Task {
                        await authSession.completeBootstrap(
                            token: token,
                            email: email,
                            password: password,
                            displayName: displayName,
                            familyName: familyName,
                            timeZone: TimeZone.current.identifier
                        )
                    }
                }
                .disabled(email.isEmpty || password.count < 8 || displayName.isEmpty || familyName.isEmpty || authSession.isAuthenticating)
            }
        }
        .navigationTitle("First Parent")
    }
}

@MainActor
struct ParentEnrollmentView: View {
    @Environment(AppEnvironment.self) private var environment
    private var authSession: AuthSession { environment.authSession }
    @State private var email: String
    @State private var password = ""
    @State private var displayName = ""
    let token: String

    init(token: String, suggestedEmail: String?) {
        self.token = token
        _email = State(initialValue: suggestedEmail ?? "")
    }

    var body: some View {
        Form {
            if let error = authSession.errorMessage { ErrorBanner(message: error) }
            Section("Join as a parent") {
                TextField("Your name", text: $displayName).textContentType(.name)
                    .accessibilityIdentifier("enrollment.parent.name")
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .accessibilityIdentifier("enrollment.parent.email")
                SecureField("Password", text: $password).textContentType(.password)
                    .accessibilityIdentifier("enrollment.parent.password")
                Button("Accept Invitation") {
                    Task { await authSession.acceptEnrollment(token: token, email: email, password: password, displayName: displayName) }
                }
                .disabled(email.isEmpty || password.count < 8 || displayName.isEmpty || authSession.isAuthenticating)
                .accessibilityIdentifier("enrollment.parent.submit")
            }
        }
        .navigationTitle("Parent Invitation")
    }
}

@MainActor
struct ChildEnrollmentView: View {
    @Environment(AppEnvironment.self) private var environment
    private var authSession: AuthSession { environment.authSession }
    @State private var username = ""
    @State private var secret = ""
    @State private var confirmation = ""
    @State private var kind = ChildCredentialKind.pin
    @State private var deviceName = UIDevice.current.name
    let token: String
    let childName: String?

    var body: some View {
        Form {
            if let error = authSession.errorMessage { ErrorBanner(message: error) }
            Section(childName.map { "Set up \($0)" } ?? "Set up child login") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .textContentType(.username)
                    .accessibilityIdentifier("enrollment.child.username")
                Picker("Login method", selection: $kind) {
                    Text("PIN").tag(ChildCredentialKind.pin)
                    Text("Password").tag(ChildCredentialKind.password)
                }
                .pickerStyle(.segmented)
                SecureField(kind == .pin ? "PIN" : "Password", text: $secret)
                    .keyboardType(kind == .pin ? .numberPad : .default)
                    .accessibilityIdentifier("enrollment.child.secret")
                SecureField("Confirm \(kind == .pin ? "PIN" : "password")", text: $confirmation)
                    .keyboardType(kind == .pin ? .numberPad : .default)
                    .accessibilityIdentifier("enrollment.child.confirmation")
                if kind == .pin {
                    Text("Use \(environment.serverProfile?.childPin.minimumLength ?? 6) to \(environment.serverProfile?.childPin.maximumLength ?? 12) digits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("Device name", text: $deviceName)
                    .accessibilityIdentifier("enrollment.child.deviceName")
                Button("Finish Child Setup") {
                    Task {
                        await authSession.completeChildEnrollment(
                            token: token,
                            username: username,
                            secret: secret,
                            credentialKind: kind,
                            deviceName: deviceName
                        )
                    }
                }
                .disabled(!canSubmit || authSession.isAuthenticating)
                .accessibilityIdentifier("enrollment.child.submit")
            }
        }
        .navigationTitle("Child Invitation")
    }

    private var canSubmit: Bool {
        guard username.count >= 3, secret == confirmation else { return false }
        if kind == .pin {
            let policy = environment.serverProfile?.childPin ?? .standard
            return secret.count >= policy.minimumLength && secret.count <= policy.maximumLength && secret.allSatisfy(\.isNumber)
        }
        return secret.count >= 8
    }
}

@MainActor
struct ChildSignInView: View {
    @Environment(AppEnvironment.self) private var environment
    private var authSession: AuthSession { environment.authSession }
    @State private var username = ""
    @State private var secret = ""
    @State private var deviceName = UIDevice.current.name

    var body: some View {
        Form {
            if let error = authSession.errorMessage { ErrorBanner(message: error) }
            Section("Child sign in") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .textContentType(.username)
                    .accessibilityIdentifier("childLogin.username")
                SecureField("Password or PIN", text: $secret)
                    .textContentType(.password)
                    .accessibilityIdentifier("childLogin.secret")
                TextField("Device name", text: $deviceName)
                    .accessibilityIdentifier("childLogin.deviceName")
                Button("Sign In") {
                    Task { await authSession.loginChild(username: username, secret: secret, deviceName: deviceName) }
                }
                .disabled(username.isEmpty || secret.isEmpty || authSession.isAuthenticating)
                .accessibilityIdentifier("childLogin.submit")
            }
        }
        .navigationTitle("Kid Access")
    }
}

@MainActor
struct ServerSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirmingSwitch = false

    var body: some View {
        if let profile = environment.serverProfile {
            Section("Family server") {
                LabeledContent("Address", value: profile.origin.host ?? profile.origin.absoluteString)
                LabeledContent("Connection", value: profile.origin.scheme == "https" ? "Encrypted" : "Private HTTP")
                if !profile.capabilities.push {
                    Label("Notifications are available in Inbox; push alerts are not enabled on this server.", systemImage: "bell.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Switch Family Server", role: .destructive) {
                    confirmingSwitch = true
                }
                .accessibilityIdentifier("settings.switchServer")
            }
            .confirmationDialog("Switch family server?", isPresented: $confirmingSwitch, titleVisibility: .visible) {
                Button("Sign Out and Switch Server", role: .destructive) {
                    Task { await environment.forgetServer() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This signs out and removes this server's credentials from this iPhone. Your family data remains on the server.")
            }
        }
    }
}

private extension EnrollmentKind {
    var label: String {
        switch self {
        case .bootstrap: "First parent"
        case .parent: "Parent"
        case .child: "Child"
        }
    }
}
