import SwiftUI

struct ActivityTimeline: View {
    let items: [ActivityTimelineItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(color(for: item.kind))
                            .frame(width: 12, height: 12)
                        Rectangle()
                            .fill(AppColors.separator)
                            .frame(width: 1)
                    }
                    .frame(width: 16)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Formatters.exactTime(item.date)) — \(item.title)")
                            .font(.body.weight(.medium))
                        Text(item.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 16)

                    Spacer()
                }
            }
        }
    }

    private func color(for kind: ActivityEventKind) -> Color {
        switch kind {
        case .motion, .all: .blue
        case .caution: .yellow
        case .critical: .red
        case .deviceStatus: .orange
        }
    }
}
