import SwiftUI

enum AppColors {
    static var groupedBackground: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color.gray.opacity(0.08)
        #endif
    }

    static var secondaryGroupedBackground: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color.gray.opacity(0.14)
        #endif
    }

    static var separator: Color {
        #if os(iOS)
        Color(.separator)
        #else
        Color.secondary.opacity(0.25)
        #endif
    }
}

extension View {
    @ViewBuilder
    func inlineNavigationTitleIfAvailable() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
