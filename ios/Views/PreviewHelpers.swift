import SwiftUI

struct MainTabPreview: View {
    let scenario: PreviewScenario

    var body: some View {
        let services = AppServiceContainer.mock(scenario: scenario)
        MainTabView(services: services)
            .environmentObject(AppRootViewModel(services: services))
    }
}
