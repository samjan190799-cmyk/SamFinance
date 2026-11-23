import Foundation

/// Реклама Яндекса. Идентификатор рекламного блока задаёт сборка (секрет GitHub YANDEX_ADS_BANNER_ID, шаг «Inject Ads Settings»
/// в testflight.yml). Без идентификатора рекламы нет совсем: ни SDK, ни запроса на отслеживание. Так сборки для разработки,
/// тестов и снимков App Store остаются без рекламы.
struct YandexAdsConfig: Sendable, Equatable {
    /// Ключ Info.plist, в который сборка кладёт идентификатор блока
    enum InfoKey {
        static let bannerUnitID = "YandexAdsBannerUnitID"
        /// «true» только в проверочных сборках (флажок ads_debug в testflight.yml): баннер пишет на экране стадию и ошибку
        static let showsErrors = "YandexAdsShowErrors"
    }

    /// Демо-блок Яндекса: отдаёт тестовую рекламу. Для проверки интеграции, а не для выпуска.
    static let demoBannerUnitID = "demo-banner-yandex"

    /// Идентификатор баннерного блока вида R-M-…-…; nil, если сборка без рекламы
    var bannerUnitID: String?

    /// Показывать ли на месте баннера, на какой стадии он и почему не загрузился. В выпускных сборках всегда false.
    var showsErrors: Bool

    static let standard = YandexAdsConfig(info: Bundle.main.infoDictionary ?? [:])

    init(bannerUnitID: String?, showsErrors: Bool = false) {
        self.bannerUnitID = bannerUnitID
        self.showsErrors = showsErrors
    }

    /// Настройки из словаря Info.plist. Пустое значение и неподставленное «$(…)» считаются отсутствующими.
    init(info: [String: Any]) {
        let raw = (info[InfoKey.bannerUnitID] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty, !raw.hasPrefix("$(") {
            self.bannerUnitID = raw
        } else {
            self.bannerUnitID = nil
        }
        self.showsErrors = (info[InfoKey.showsErrors] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    var isBannerEnabled: Bool {
        bannerUnitID != nil
    }

    /// Показывать ли рекламу сейчас: нужен блок, и это не режим снимков для App Store или ролика
    static func shouldShowAds(config: YandexAdsConfig, isScreenshotMode: Bool) -> Bool {
        config.isBannerEnabled && !isScreenshotMode
    }
}
