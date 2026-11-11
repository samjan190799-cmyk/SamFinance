import Foundation

/// Реклама Яндекса. Идентификатор рекламного блока задаёт сборка (секрет GitHub YANDEX_ADS_BANNER_ID, шаг «Inject Ads Settings»
/// в testflight.yml). Без идентификатора рекламы нет совсем: ни SDK, ни запроса на отслеживание. Так сборки для разработки,
/// тестов и снимков App Store остаются без рекламы.
struct YandexAdsConfig: Sendable, Equatable {
    /// Ключ Info.plist, в который сборка кладёт идентификатор блока
    enum InfoKey {
        static let bannerUnitID = "YandexAdsBannerUnitID"
    }

    /// Демо-блок Яндекса: отдаёт тестовую рекламу. Для проверки интеграции, а не для выпуска.
    static let demoBannerUnitID = "demo-banner-yandex"

    /// Идентификатор баннерного блока вида R-M-…-…; nil, если сборка без рекламы
    var bannerUnitID: String?

    static let standard = YandexAdsConfig(info: Bundle.main.infoDictionary ?? [:])

    init(bannerUnitID: String?) {
        self.bannerUnitID = bannerUnitID
    }

    /// Настройки из словаря Info.plist. Пустое значение и неподставленное «$(…)» считаются отсутствующими.
    init(info: [String: Any]) {
        let raw = (info[InfoKey.bannerUnitID] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty, !raw.hasPrefix("$(") {
            self.bannerUnitID = raw
        } else {
            self.bannerUnitID = nil
        }
    }

    var isBannerEnabled: Bool {
        bannerUnitID != nil
    }

    /// Показывать ли рекламу сейчас: нужен блок, и это не режим снимков для App Store или ролика
    static func shouldShowAds(config: YandexAdsConfig, isScreenshotMode: Bool) -> Bool {
        config.isBannerEnabled && !isScreenshotMode
    }
}
