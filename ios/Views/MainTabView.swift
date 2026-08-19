import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var rootViewModel: AppRootViewModel
    let services: AppServiceContainer

    var body: some View {
        TabView(selection: $rootViewModel.selectedTab) {
            HomeView(viewModel: HomeViewModel(services: services)) {
                rootViewModel.selectedTab = .activity
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(MainTab.home)

            ActivityView(viewModel: ActivityViewModel(services: services))
                .tabItem {
                    Label("Activity", systemImage: "clock.fill")
                }
                .tag(MainTab.activity)

            SettingsView(viewModel: SettingsViewModel(services: services))
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(MainTab.settings)
        }
    }
}
