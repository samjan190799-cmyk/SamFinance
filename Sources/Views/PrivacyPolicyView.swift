import SwiftUI

/// Политика конфиденциальности внутри приложения: текст берётся из Resources/Legal и работает без сети
struct PrivacyPolicyView: View {
    private let language = AppLanguage.current
    private let blocks = LegalDocument.privacyPolicy(for: AppLanguage.current)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if language == .armenian {
                    Text(String(localized: "Текст политики доступен на русском и английском языках."))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textTertiary)
                }

                if blocks.isEmpty {
                    Text(String(localized: "Не удалось открыть текст политики."))
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textSecondary)
                }

                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .tint(Theme.accent)
        .monoScreen()
        .navigationTitle(String(localized: "Политика конфиденциальности"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func blockView(_ block: LegalBlock) -> some View {
        switch block {
        case .title(let text):
            Text(text)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        case .heading(let text):
            Text(text)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 14)
        case .paragraph(let text):
            Text(styled(text))
                .font(.system(size: 15))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: "•")
                    .foregroundColor(Theme.accent)
                Text(styled(text))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 15))
        }
    }

    /// Жирный текст и ссылки из Markdown; если разобрать не удалось, строка показывается как есть
    private func styled(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
