import UIKit

/// Менеджер тактильной отдачи (Haptic Feedback), соответствующий стандартам iOS 17+ и Swift 6.
@MainActor
public final class HapticManager {
    public static let shared = HapticManager()
    
    private init() {}
    
    /// Воспроизведение стандартных уведомлений (успех, ошибка, предупреждение)
    public func trigger(_ feedbackType: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(feedbackType)
    }
    
    /// Воспроизведение физического удара определенной силы
    public func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    /// Воспроизведение тактильного щелчка при изменении выбора элемента (например, прокрутка)
    public func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}
