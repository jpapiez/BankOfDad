import Observation
import SwiftUI

@MainActor
@Observable
final class VersionViewModel {
    enum State: Equatable {
        case loading
        case loaded(ServerVersion, VersionCompatibility)
        case predatesVersioning
        case failed(String)
    }

    var state: State = .loading

    func load(api: APIClient) async {
        do {
            let server: ServerVersion = try await api.get("/version", requiresAuth: false)
            state = .loaded(server, VersionCompatibility.evaluate(server: server))
        } catch APIError.problem(let problem) where problem.status == 404 {
            state = .predatesVersioning
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// App and server versions with a compatibility verdict, to make client/server mismatches obvious.
@MainActor
struct VersionSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = VersionViewModel()
    let idPrefix: String

    var body: some View {
        Section("About") {
            LabeledContent("App", value: "\(ClientVersion.display) · api\(ClientVersion.apiLevel)")
                .accessibilityIdentifier("\(idPrefix).appVersion")
            if environment.isDemo {
                LabeledContent("Server", value: "Demo (offline)")
                    .accessibilityIdentifier("\(idPrefix).serverVersion")
            } else {
                switch viewModel.state {
                case .loading:
                    LabeledContent("Server", value: "Checking…")
                        .accessibilityIdentifier("\(idPrefix).serverVersion")
                case .loaded(let server, let compatibility):
                    LabeledContent("Server", value: "\(server.version) · \(String(server.commit.prefix(7))) · api\(server.apiLevel)")
                        .accessibilityIdentifier("\(idPrefix).serverVersion")
                    if compatibility.isProblem { warning(compatibility.message) }
                case .predatesVersioning:
                    LabeledContent("Server", value: "Unknown (old)")
                        .accessibilityIdentifier("\(idPrefix).serverVersion")
                    warning(VersionCompatibility.serverPredatesVersioning.message)
                case .failed(let message):
                    LabeledContent("Server", value: "Unavailable")
                        .accessibilityIdentifier("\(idPrefix).serverVersion")
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: environment.isDemo) { if !environment.isDemo { await viewModel.load(api: environment.apiClient) } }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .accessibilityIdentifier("\(idPrefix).versionWarning")
    }
}
