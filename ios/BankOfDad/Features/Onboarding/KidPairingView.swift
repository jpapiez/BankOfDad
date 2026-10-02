import SwiftUI
import UIKit

@MainActor
struct KidPairingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    private var authSession: AuthSession { environment.authSession }
    @State private var code = ""
    @State private var deviceName = UIDevice.current.name
    @State private var showingScanner = false

    var body: some View {
        Form {
            if let error = authSession.errorMessage { ErrorBanner(message: error) }
            Section {
                Text("Ask your parent for the pairing code or scan the QR code from their Family screen.")
                    .foregroundStyle(.secondary)
                TextField("K7Q-4MZ-2P", text: $code)
                    .font(.title2.monospaced())
                    .textInputAutocapitalization(.characters)
                    .onChange(of: code) { _, newValue in code = PairingCode.display(newValue) }
                    .accessibilityIdentifier("pairing.code")
                TextField("Device name", text: $deviceName)
                    .accessibilityIdentifier("pairing.deviceName")
                Button("Join my family") { pair() }
                    .disabled(PairingCode.normalized(code).isEmpty || authSession.isAuthenticating)
                    .accessibilityIdentifier("pairing.join")
                if authSession.isAuthenticating { ProgressView() }
                Button { showingScanner = true } label: {
                    Label("Scan QR code", systemImage: "qrcode.viewfinder")
                }
                .accessibilityIdentifier("pairing.scan")
            } header: {
                Text("Pair this device")
            }
        }
        .navigationTitle("Kid pairing")
        .sheet(isPresented: $showingScanner) {
            CodeScannerView { scanned in
                code = PairingCode.display(scanned)
                showingScanner = false
                pair()
            }
        }
        .onAppear(perform: consumePendingCode)
        .onChange(of: router.pendingPairingCode) { _, _ in consumePendingCode() }
    }

    private func consumePendingCode() {
        guard let pending = router.pendingPairingCode else { return }
        // Clear it so the same link can be opened again and it doesn't linger after pairing.
        router.pendingPairingCode = nil
        code = PairingCode.display(pending)
        pair()
    }

    private func pair() {
        Task { await authSession.pair(code: code, deviceName: deviceName.isEmpty ? UIDevice.current.name : deviceName) }
    }
}
