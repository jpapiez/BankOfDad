import SwiftUI

struct KidRootView: View {
    var body: some View {
        TabView {
            NavigationStack { MyLoansView() }
                .tabItem { Label("What I Owe", systemImage: "bicycle") }
            NavigationStack { InboxView() }
                .tabItem { Label("Inbox", systemImage: "bell.fill") }
            NavigationStack { KidSettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.kidAccent)
    }
}
