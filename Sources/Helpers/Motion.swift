import SwiftUI

/// Движение «Пульса»: пружины для переходов, нажатие с пружинкой и появление блоков по очереди.
/// При включённом «Уменьшении движения» блоки только проявляются, без сдвигов и поворотов.
enum Motion {
    /// Основная пружина: переключатели, вкладки, смена карты
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// Упругая пружина для мелочей: нажатия, отметки, кнопки
    static let bouncy = Animation.spring(response: 0.3, dampingFraction: 0.6)
    /// Смена цифр в суммах
    static let digits = Animation.snappy(duration: 0.28)
    /// Задержка между соседними блоками при появлении экрана
    static let stagger = 0.05
}

/// Кнопка слегка сжимается под пальцем и пружинит обратно
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(Motion.bouncy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// Блок проявляется и поднимается на место при первом показе
private struct AppearAnimation: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 20)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.97, anchor: .top)
            .onAppear {
                guard !isVisible else { return }
                withAnimation(Motion.spring.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    /// Появление снизу с проявлением; delay задаёт очередь, когда блоков несколько
    func appearAnimation(delay: Double = 0) -> some View {
        modifier(AppearAnimation(delay: delay))
    }

    /// Появление по номеру блока на экране: каждый следующий чуть позже
    func appearAnimation(order: Int) -> some View {
        modifier(AppearAnimation(delay: Double(order) * Motion.stagger))
    }
}
