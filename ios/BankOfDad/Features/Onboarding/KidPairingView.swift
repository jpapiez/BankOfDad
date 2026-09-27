import SwiftUI
import UIKit

struct KidPairingView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(AppRouter.self) private var router
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
                TextField("Device name", text: $deviceName)
                Button("Join my family") { pair() }
                    .disabled(PairingCode.normalized(code).isEmpty || authSession.isAuthenticating)
                if authSession.isAuthenticating { ProgressView() }
                Button { showingScanner = true } label: {
                    Label("Scan QR code", systemImage: "qrcode.viewfinder")
                }
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
        .onChange(of: router.pendingPairingCode) { _, newValue in
            guard let newValue else { return }
            code = PairingCode.display(newValue)
            pair()
        }
    }

    private func pair() {
        Task { await authSession.pair(code: code, deviceName: deviceName.isEmpty ? UIDevice.current.name : deviceName) }
    }
}
