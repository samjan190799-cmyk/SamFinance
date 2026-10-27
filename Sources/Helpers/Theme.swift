import SwiftUI

/// Токены дизайна SamFinance «Пульс»: графитовый фон, лаймовый акцент, крупные скруглённые цифры.
enum Theme {
    static let background = Color(hex: "#111214")
    static let surface = Color(hex: "#1C1D21")
    static let surfaceRaised = Color(hex: "#2A2B30")
    static let line = Color(hex: "#34353B")
    static let hairline = Color(hex: "#26272C")
    static let tabBar = Color(hex: "#16171A")
    static let textSecondary = Color(hex: "#9B9DA4")
    static let textTertiary = Color(hex: "#8B8D94")
    /// Лаймовый акцент: главные кнопки, активные вкладки, рост
    static let accent = Color(hex: "#C6F432")
    /// Текст поверх лайма
    static let onAccent = Color(hex: "#111214")
    /// Тёмный лайм под белым текстом: системные кнопки смахивания в списках
    static let accentStrong = Color(hex: "#5E7A0F")
    /// Необратимые действия: удаление
    static let danger = Color(hex: "#FF6B6B")

    /// Цвета долей категорий: от самой крупной к самой мелкой
    static let shades: [Color] = [
        Color(hex: "#C6F432"),
        Color(hex: "#F4F4F5"),
        Color(hex: "#9B9DA4"),
        Color(hex: "#5E6068"),
        Color(hex: "#3A3B41")
    ]

    /// Шрифт для сумм и крупных цифр
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Яркость цвета от 0 (чёрный) до 1 (белый)
    static func luminance(hex: String) -> Double {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return 0.299 * red + 0.587 * green + 0.114 * blue
    }

    /// Светлая ли заливка: поверх светлой нужен тёмный текст
    static func isLight(hex: String) -> Bool {
        luminance(hex: hex) > 0.6
    }

    /// Цвет для полосок и значков на тёмном фоне: слишком тёмный цвет подсвечивается, иначе он слился бы с фоном
    static func visibleTint(hex: String) -> Color {
        guard luminance(hex: hex) < 0.3 else { return Color(hex: hex) }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        func lifted(_ shift: UInt64) -> Double {
            let channel = Double((value >> shift) & 0xFF)
            return (channel + (255 - channel) * 0.6) / 255
        }
        return Color(.sRGB, red: lifted(16), green: lifted(8), blue: lifted(0), opacity: 1)
    }
}

/// Мелкая подпись над значением
struct MonoLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.textSecondary)
    }
}

/// Круглая кнопка с иконкой на графитовой подложке
struct MonoCircleButton: View {
    let systemName: String
    let label: String
    var filled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(filled ? Theme.onAccent : .white)
                .frame(width: 44, height: 44)
                .background(filled ? Theme.accent : Theme.surfaceRaised)
                .clipShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88))
        .accessibilityLabel(label)
    }
}

/// Переключатель в виде капсулы: лаймовая подложка перетекает к выбранному варианту, остальные приглушены
struct MonoSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                segment(for: option)
            }
        }
        .padding(4)
        .background(Theme.surface)
        .clipShape(Capsule())
    }

    private func segment(for option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            guard option != selection else { return }
            HapticManager.shared.selection()
            withAnimation(Motion.spring) {
                selection = option
            }
        } label: {
            Text(title(option))
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Theme.onAccent : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Theme.accent)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }
}

/// Скруглённый квадрат с первой буквой названия вместо логотипа бренда
struct MonoInitialBadge: View {
    let title: String
    var size: CGFloat = 44

    var body: some View {
        Text(String(title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(Theme.number(16, weight: .bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
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
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            if let trailing {
                Button {
                    onTrailingTap?()
                } label: {
                    Text(trailing)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(trailingColor)
                }
            }
        }
    }
}

/// Главная кнопка: лаймовая капсула с тёмным текстом
struct PrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Theme.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.4)
        .animation(Motion.spring, value: isEnabled)
    }
}

extension View {
    /// Графитовая плитка со скруглёнными углами
    func monoSurface(cornerRadius: CGFloat = 24) -> some View {
        self
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// Фон экрана и тёмная схема
    func monoScreen() -> some View {
        self
            .background(Theme.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }

    /// Строка List без системного фона, разделителей и отступов: экран выглядит как обычная прокрутка «Пульса»
    func monoListRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Тёмный фон для экранов на основе Form и List
    func monoForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
    }
}
