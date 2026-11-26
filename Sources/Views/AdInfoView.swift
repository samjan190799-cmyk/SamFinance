import SwiftUI

/// О рекламе в приложении: что используется для её показа, как отключить персонализацию и как пожаловаться на объявление.
/// App Store (2.5.18) требует, чтобы приложение с рекламой давало увидеть, что используется для показа, и пожаловаться.
struct AdInfoView: View {
    /// Жалобы Яндекса на объявления: сюда и в меню самого объявления жалуются на неподходящую рекламу
    static let complaintURL = URL(string: "https://yandex.ru/support/direct/troubleshooting/complain.html")!
    static let yandexPrivacyURL = URL(string: "https://yandex.ru/legal/confidential/")!

    var body: some View {
        Form {
            Section {
                Text(String(localized: "В приложении показывается реклама Яндекса. Для её показа Яндекс получает технические данные устройства: IP-адрес (по нему примерно определяется регион), модель и версию iOS, язык, идентификаторы устройства, рекламный идентификатор (только если вы разрешили отслеживание), сведения о показах и нажатиях на рекламу."))
            } header: {
                Text(String(localized: "Что используется для рекламы"))
            }

            Section {
                Text(String(localized: "Операции, карты, долги, копилки, подписки, вопросы к ИИ-помощнику и другие ваши финансовые данные в рекламу не передаются."))
            } header: {
                Text(String(localized: "Что не используется"))
            }

            Section {
                Text(String(localized: "Персональную рекламу можно отключить: Настройки iOS → Конфиденциальность и безопасность → Отслеживание."))
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: settings) {
                        Label(String(localized: "Открыть настройки iOS"), systemImage: "gearshape")
                    }
                }
            } header: {
                Text(String(localized: "Отслеживание"))
            }

            Section {
                Text(String(localized: "Неподходящее объявление можно отметить в меню самого объявления или написать о нём Яндексу."))
                Link(destination: Self.complaintURL) {
                    Label(String(localized: "Пожаловаться на рекламу"), systemImage: "exclamationmark.bubble")
                }
                Link(destination: Self.yandexPrivacyURL) {
                    Label(String(localized: "Политика конфиденциальности Яндекса"), systemImage: "hand.raised")
                }
            } header: {
                Text(String(localized: "Жалобы"))
            }
        }
        .navigationTitle(String(localized: "Реклама"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
