import SwiftUI

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            Text(document.content)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(document.title)
        .inlineNavigationTitle()
    }
}

enum LegalDocument: String, CaseIterable, Identifiable {
    case privacyPolicy = "PrivacyPolicy"
    case termsAndConditions = "TermsAndConditions"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacyPolicy:
            "Privacy Policy"
        case .termsAndConditions:
            "Terms and Conditions"
        }
    }

    var content: AttributedString {
        guard let url = documentURL,
              let markdown = try? String(contentsOf: url, encoding: .utf8),
              let attributedString = try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
              ) else {
            return AttributedString("This document is unavailable.")
        }

        return attributedString
    }

    private var documentURL: URL? {
        Bundle.elephResourceBundle.url(forResource: rawValue, withExtension: "md", subdirectory: "Legal")
            ?? Bundle.elephResourceBundle.url(forResource: rawValue, withExtension: "md")
    }
}

#Preview {
    NavigationStack {
        LegalDocumentView(document: .privacyPolicy)
    }
}

private extension View {
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
