import SwiftUI

struct DeviceConnectionBanner: View {
    let device: MonitorDevice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: device.connectionStatus.symbol)
                .font(.title2)
                .foregroundStyle(device.connectionStatus.tint)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.connectionStatus.title)
                    .font(.headline)
                Text(connectionCopy)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if device.connectionStatus == .offline {
                    Text("Motion activity may be incomplete while the monitor is offline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(device.connectionStatus.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(device.connectionStatus.tint.opacity(0.35))
        }
    }

    private var connectionCopy: String {
        switch device.connectionStatus {
        case .online:
            "Last connected just now"
        case .offline:
            "Disconnected \(Formatters.relative(device.lastConnectedAt))"
        case .connecting:
            "Trying to reconnect"
        }
    }
}

#Preview {
    DeviceConnectionBanner(device: MockData.stableDevice(connectionStatus: .offline))
        .padding()
}
