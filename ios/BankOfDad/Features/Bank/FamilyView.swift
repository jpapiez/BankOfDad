import CoreImage.CIFilterBuiltins
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class FamilyViewModel {
    var family: FamilyDto?
    var pairing: PairingCodeResponse?
    var invite: InviteResponse?
    var isLoading = false
    var error: String?

    func load(service: FamilyService) async {
        isLoading = true; defer { isLoading = false }
        do { family = try await service.family(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func addChild(name: String, color: String, service: FamilyService) async {
        do { _ = try await service.addChild(displayName: name, avatarColor: color); await load(service: service) }
        catch { self.error = error.localizedDescription }
    }

    func generatePairing(childId: UUID, service: FamilyService) async {
        do { pairing = try await service.pairingCode(childId: childId); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func revokeDevices(childId: UUID, service: FamilyService) async {
        do { try await service.revokeDevices(childId: childId); await load(service: service) }
        catch { self.error = error.localizedDescription }
    }

    func invite(email: String?, service: FamilyService) async {
        do { invite = try await service.invite(email: email?.isEmpty == true ? nil : email); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

@MainActor
struct FamilyView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = FamilyViewModel()
    @State private var addingChild = false
    @State private var inviteEmail = ""
    @State private var selectedChild: ChildDto?

    var body: some View {
        List {
            if let error = viewModel.error { ErrorBanner(message: error) }
            Section("Children") {
                ForEach(viewModel.family?.children ?? []) { child in
                    HStack {
                        HStack {
                            AvatarView(name: child.displayName, colorHex: child.avatarColor)
                            VStack(alignment: .leading) {
                                Text(child.displayName).font(.headline)
                                Text("\(child.pairedDeviceCount) paired device\(child.pairedDeviceCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("family.child.\(child.displayName).devices")
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedChild = child }
                        Menu {
                            Button("Generate pairing code") { Task { await viewModel.generatePairing(childId: child.id, service: environment.familyService) } }
                                .accessibilityIdentifier("family.generatePairing")
                            Button("Revoke devices", role: .destructive) { Task { await viewModel.revokeDevices(childId: child.id, service: environment.familyService) } }
                                .accessibilityIdentifier("family.revokeDevices")
                        } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel("Actions for \(child.displayName)")
                        .accessibilityIdentifier("family.child.\(child.displayName).actions")
                        Button { selectedChild = child } label: { Image(systemName: "chevron.right").foregroundStyle(.secondary).frame(width: 32, height: 44) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Loans and bills for \(child.displayName)")
                            .accessibilityIdentifier("family.child.\(child.displayName).open")
                    }
                }
                Button { addingChild = true } label: { Label("Add child", systemImage: "plus") }
                    .accessibilityIdentifier("family.addChild")
            }
            Section("Co-parents") {
                ForEach(viewModel.family?.parents ?? []) { parent in
                    Label(parent.displayName, systemImage: "person.fill")
                        .accessibilityIdentifier("family.parent.\(parent.displayName)")
                }
                TextField("Invite email (optional)", text: $inviteEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("family.inviteEmail")
                Button("Invite co-parent") { Task { await viewModel.invite(email: inviteEmail, service: environment.familyService) } }
                    .accessibilityIdentifier("family.invite")
                if let invite = viewModel.invite {
                    ShareLink(item: invite.inviteCode) {
                        Label("Share invite \(invite.inviteCode)", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("family.inviteShare")
                    .accessibilityValue(invite.inviteCode)
                    Text("Expires \(AppFormatters.timestamp(invite.expiresAt))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(viewModel.family?.name ?? "Family")
        .toolbar { Button { addingChild = true } label: { Label("Add child", systemImage: "person.badge.plus") }.accessibilityIdentifier("family.addChildToolbar") }
        .sheet(isPresented: $addingChild) { AddChildSheet { name, color in await viewModel.addChild(name: name, color: color, service: environment.familyService) } }
        .sheet(item: $viewModel.pairing) { response in PairingCodeSheet(response: response) }
        .navigationDestination(item: $selectedChild) { child in ChildDetailView(child: child) }
        .task { await viewModel.load(service: environment.familyService) }
        .refreshable { await viewModel.load(service: environment.familyService) }
    }
}

struct AddChildSheet: View {
    let onAdd: @MainActor (String, String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = "#4F8EF7"
    private let colors = ["#4F8EF7", "#FF9F1C", "#2EC4B6", "#E71D36", "#7B61FF"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Child name", text: $name)
                    .accessibilityIdentifier("addChild.name")
                Picker("Avatar color", selection: $color) {
                    ForEach(colors, id: \.self) { hex in
                        HStack { Circle().fill(Color(hex: hex) ?? .blue).frame(width: 18, height: 18); Text(hex) }.tag(hex)
                    }
                }
                .accessibilityIdentifier("addChild.color")
            }
            .navigationTitle("Add child")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("addChild.cancel") }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { Task { await onAdd(name, color); dismiss() } }.disabled(name.isEmpty).accessibilityIdentifier("addChild.add") }
            }
        }
    }
}

struct PairingCodeSheet: View {
    let response: PairingCodeResponse
    @Environment(\.dismiss) private var dismiss
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(PairingCode.display(response.code))
                    .font(.system(.largeTitle, design: .monospaced).bold())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("pairingSheet.code")
                if let image = QRCode.makeImage(from: response.qrPayload) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .accessibilityLabel("Pairing QR code")
                        .accessibilityIdentifier("pairingSheet.qr")
                }
                Text("Expires in \(remainingSeconds) seconds")
                    .foregroundStyle(remainingSeconds < 60 ? .red : .secondary)
                    .accessibilityIdentifier("pairingSheet.expires")
                ShareLink(item: response.qrPayload) { Label("Share pairing link", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier("pairingSheet.share")
                Spacer()
            }
            .padding()
            .navigationTitle("Pair child")
            .toolbar { Button("Done") { dismiss() }.accessibilityIdentifier("pairingSheet.done") }
            .onReceive(timer) { now = $0 }
        }
    }

    private var remainingSeconds: Int { max(0, Int(response.expiresAt.timeIntervalSince(now))) }
}

enum QRCode {
    static func makeImage(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
