import SwiftUI

struct SettingsRow: View {
    let title: String
    let detail: String?
    let systemImage: String
    var tint: Color = .blue

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
