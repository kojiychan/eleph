import SwiftUI

struct OnboardingProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(currentStep + 1), total: Double(totalSteps))
            Label(
                currentStep + 1 >= totalSteps ? "Done" : "Step \(currentStep + 1) of \(totalSteps)",
                systemImage: currentStep + 1 >= totalSteps ? "checkmark.circle.fill" : "circle.dotted"
            )
            .font(.caption)
            .foregroundStyle(currentStep + 1 >= totalSteps ? .green : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
