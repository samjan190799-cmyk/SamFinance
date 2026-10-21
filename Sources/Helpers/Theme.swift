import SwiftUI

/// Токены дизайна SamFinance Mono: чёрный фон, белый текст, тонкие линии и один акцент для роста и прогресса.
enum Theme {
    static let background = Color(hex: "#000000")
    static let surface = Color(hex: "#0E0E10")
    static let surfaceRaised = Color(hex: "#161618")
    static let line = Color(hex: "#26262A")
    static let hairline = Color(hex: "#1C1C1F")
    static let textSecondary = Color(hex: "#A1A1A6")
    static let textTertiary = Color(hex: "#8E8E93")
    static let accent = Color(hex: "#8CF0C0")

    /// Оттенки серого для долей категорий: от самой крупной к самой мелкой
    static let shades: [Color] = [
        Color(hex: "#FFFFFF"),
        Color(hex: "#C7C7CC"),
        Color(hex: "#8E8E93"),
        Color(hex: "#5A5A5E"),
        Color(hex: "#3A3A3C")
    ]

    /// Светлая ли заливка: поверх светлой нужен тёмный текст
    static func isLight(hex: String) -> Bool {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return 0.299 * red + 0.587 * green + 0.114 * blue > 0.6
    }
}

/// Мелкая подпись заглавными буквами над значением
struct MonoLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .medium))
            .tracking(1)
            .foregroundColor(Theme.textTertiary)
    }
}

/// Круглая кнопка-контур с иконкой
struct MonoCircleButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
        }
        .accessibilityLabel(label)
    }
}

/// Переключатель в виде капсулы: активный вариант белый, остальные приглушены
struct MonoSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                segment(for: option)
            }
        }
        .padding(4)
        .background(Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
    }

    private func segment(for option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            HapticManager.shared.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = option
            }
        } label: {
            Text(title(option))
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .black : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(isSelected ? Color.white : Color.clear)
                .clipShape(Capsule())
        }
    }
}

/// Кружок с первой буквой названия вместо логотипа бренда
struct MonoInitialBadge: View {
    let title: String
    var size: CGFloat = 44

    var body: some View {
        Text(String(title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Theme.line, lineWidth: 1))
    }
}

/// Тонкая линия-разделитель между строками списка
struct MonoDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}

/// Заголовок раздела со ссылкой справа
struct MonoSectionHeader: View {
    let title: String
    var trailing: String? = nil
    var trailingColor: Color = Theme.textSecondary
    var onTrailingTap: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            if let trailing {
                Button {
                    onTrailingTap?()
                } label: {
                    Text(trailing)
                        .font(.system(size: 14))
                        .foregroundColor(trailingColor)
                }
            }
        }
    }
}

extension View {
    /// Плоская поверхность с тонкой рамкой
    func monoSurface(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Theme.hairline, lineWidth: 1))
    }

    /// Чёрный фон экрана и тёмная схема
    func monoScreen() -> some View {
        self
            .background(Theme.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }

    /// Тёмный фон для экранов на основе Form и List
    func monoForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}
