import Foundation

enum PreviewScenario: String, CaseIterable, Identifiable {
    case normalOnline = "Normal and online"
    case cautionInactivity = "Caution inactivity"
    case criticalInactivity = "Critical inactivity"
    case recentlyDisconnected = "Recently disconnected"
    case offlineSeveralHours = "Offline for hours"
    case noActivity = "No activity"
    case onboardingIncomplete = "Onboarding incomplete"
    case onboardingComplete = "Onboarding complete"

    var id: String { rawValue }
}
