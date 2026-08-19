import SwiftUI

struct LoadingOverlay: View {
    var title = "Loading"

    var body: some View {
        ProgressView(title)
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.opacity(0.35))
    }
}
