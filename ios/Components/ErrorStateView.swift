import SwiftUI

struct ErrorStateView: View {
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
            }
        }
    }
}
