import SwiftUI

struct ParentRootView: View {
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent") }
            NavigationStack { LoansListView() }
                .tabItem { Label("Loans", systemImage: "list.bullet.rectangle") }
            NavigationStack { FamilyView() }
                .tabItem { Label("Family", systemImage: "person.3.fill") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.bankAccent)
    }
}
