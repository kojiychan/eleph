import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var rootViewModel: AppRootViewModel
    let services: AppServiceContainer

    var body: some View {
        Group {
            if rootViewModel.onboardingCompleted {
                MainTabView(services: services)
            } else {
                OnboardingView(
                    viewModel: OnboardingViewModel(services: services),
                    onComplete: rootViewModel.completeOnboarding
                )
            }
        }
        .task {
            await rootViewModel.restoreSessionIfNeeded()
        }
        .onOpenURL { url in
            Task {
                await rootViewModel.handleAuthCallback(url)
            }
        }
    }
}

#Preview("Onboarding") {
    let services = AppServiceContainer.mock(scenario: .onboardingIncomplete)
    AppRootView(services: services)
        .environmentObject(AppRootViewModel(services: services))
}
