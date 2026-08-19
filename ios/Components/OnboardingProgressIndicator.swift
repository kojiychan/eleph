import SwiftUI

struct OnboardingProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(currentStep + 1), total: Double(totalSteps))
            Text("Step \(currentStep + 1) of \(totalSteps)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
