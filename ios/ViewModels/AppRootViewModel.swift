import Foundation

@MainActor
final class AppRootViewModel: ObservableObject {
    @Published var onboardingCompleted: Bool
    @Published var selectedTab: MainTab = .home

    let services: AppServiceContainer

    init(services: AppServiceContainer) {
        self.services = services
        self.onboardingCompleted = services.identityStore.hasCompletedOnboarding()
    }

    func completeOnboarding() {
        services.identityStore.setOnboardingCompleted(true)
        onboardingCompleted = true
        selectedTab = .home
    }

    func restoreSessionIfNeeded() async {
        guard onboardingCompleted else { return }
        let hasActiveSession = await services.authenticationService.hasActiveSession()
        if !hasActiveSession {
            services.identityStore.setOnboardingCompleted(false)
            onboardingCompleted = false
        }
    }

    func handleAuthCallback(_ url: URL) async {
        guard url.scheme == "eleph" else { return }
        do {
            try await services.authenticationService.handleAuthCallback(url)
        } catch {
            return
        }
        completeOnboarding()
    }

    func signOut() async {
        do {
            try await services.authenticationService.signOut()
        } catch {
            // Local onboarding state should still reset if the remote session is already gone.
        }
        services.identityStore.setOnboardingCompleted(false)
        onboardingCompleted = false
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
