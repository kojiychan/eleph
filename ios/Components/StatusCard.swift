import SwiftUI

struct StatusCard: View {
    let state: WellnessState
    let lastMotionAt: Date?
    let isDataStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: state == .unknown ? "questionmark.circle.fill" : "heart.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(state.tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isDataStale ? WellnessState.unknown.title : state.title)
                        .font(.title2.weight(.bold))
                    Text(isDataStale ? WellnessState.unknown.subtitle : state.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Last motion")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(Formatters.relative(lastMotionAt))
                    .font(.headline)
                Text(Formatters.exactTime(lastMotionAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    StatusCard(state: .normal, lastMotionAt: Date().addingTimeInterval(-2400), isDataStale: false)
        .padding()
}
