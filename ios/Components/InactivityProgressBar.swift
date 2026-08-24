import SwiftUI

struct InactivityProgressBar: View {
    let currentInactivity: TimeInterval
    let cautionThresholdHours: Int
    let criticalThresholdHours: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current inactivity")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(Formatters.duration(currentInactivity))
                        .font(.title3.weight(.bold))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Next alert")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(nextAlertText)
                        .font(.subheadline.weight(.semibold))
                }
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let criticalSeconds = Double(criticalThresholdHours) * 3600
                let currentX = min(currentInactivity / criticalSeconds, 1) * width
                let cautionX = min(Double(cautionThresholdHours) * 3600 / criticalSeconds, 1) * width

                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Capsule()
                            .fill(.green)
                            .frame(width: max(cautionX, 8))
                        Rectangle()
                            .fill(.yellow)
                            .frame(width: max(width - cautionX - 12, 8))
                        Capsule()
                            .fill(.red)
                            .frame(width: 12)
                    }
                    .opacity(0.82)
                    .clipShape(Capsule())

                    Rectangle()
                        .fill(.primary.opacity(0.35))
                        .frame(width: 3)
                        .offset(x: max(cautionX - 1.5, 0))

                    Circle()
                        .fill(markerColor)
                        .overlay {
                            Circle()
                                .stroke(.white, lineWidth: 3)
                        }
                        .frame(width: 16, height: 16)
                        .offset(x: max(min(currentX - 8, width - 16), 0))
                        .shadow(radius: 2)
                }
            }
            .frame(height: 16)

            HStack {
                Label("Normal", systemImage: "circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Text("Caution \(cautionThresholdHours)h")
                Spacer()
                Text("Critical \(criticalThresholdHours)h")
                    .foregroundStyle(.red)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var nextAlertText: String {
        let caution = Double(cautionThresholdHours) * 3600
        let critical = Double(criticalThresholdHours) * 3600
        if currentInactivity < caution {
            return "\(Formatters.duration(caution - currentInactivity)) to caution"
        }
        if currentInactivity < critical {
            return "\(Formatters.duration(critical - currentInactivity)) to critical"
        }
        return "Critical reached"
    }

    private var markerColor: Color {
        let caution = Double(cautionThresholdHours) * 3600
        let critical = Double(criticalThresholdHours) * 3600
        if currentInactivity >= critical { return .red }
        if currentInactivity >= caution { return .yellow }
        return .green
    }
}

#Preview {
    InactivityProgressBar(currentInactivity: 2.2 * 3600, cautionThresholdHours: 12, criticalThresholdHours: 24)
        .padding()
}
