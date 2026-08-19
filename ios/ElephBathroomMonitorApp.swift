import SwiftUI

@main
struct ElephBathroomMonitorApp: App {
    private let services: AppServiceContainer
    @StateObject private var rootViewModel: AppRootViewModel

    init() {
        let services = AppServiceContainer.liveOrMock()
        self.services = services
        _rootViewModel = StateObject(wrappedValue: AppRootViewModel(services: services))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(services: services)
                .environmentObject(rootViewModel)
                .preferredColorScheme(nil)
        }
    }
}
