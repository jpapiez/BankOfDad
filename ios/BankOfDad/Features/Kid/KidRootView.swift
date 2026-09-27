import SwiftUI

struct KidRootView: View {
    var body: some View {
        TabView {
            NavigationStack { MyLoansView() }
                .tabItem { Label("My Loans", systemImage: "bicycle") }
            NavigationStack { InboxView() }
                .tabItem { Label("Inbox", systemImage: "bell.fill") }
            NavigationStack { KidSettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.kidAccent)
    }
}
