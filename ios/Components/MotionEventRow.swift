import SwiftUI

struct MotionEventRow: View {
    let event: MotionEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.walk.motion")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Motion detected")
                    .font(.body.weight(.medium))
                Text("\(Formatters.exactTime(event.detectedAt)) • \(Formatters.relative(event.detectedAt))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}
