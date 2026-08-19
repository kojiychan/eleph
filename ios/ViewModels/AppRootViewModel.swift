import Foundation

@MainActor
final class AppRootViewModel: ObservableObject {
    @Published var onboardingCompleted: Bool
    @Published var selectedTab: MainTab = .home

    private let services: AppServiceContainer

    init(services: AppServiceContainer) {
        self.services = services
        self.onboardingCompleted = services.identityStore.hasCompletedOnboarding()
    }

    func completeOnboarding() {
        services.identityStore.setOnboardingCompleted(true)
        onboardingCompleted = true
        selectedTab = .home
    }

    func resetOnboardingForPreview() {
        services.identityStore.setOnboardingCompleted(false)
        onboardingCompleted = false
    }
}

enum MainTab: Hashable {
    case home
    case activity
    case settings
}
