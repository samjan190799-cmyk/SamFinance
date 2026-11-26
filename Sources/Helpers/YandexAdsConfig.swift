import Foundation

/// Экраны с баннером: по каждому отдельно считается интервал между запросами рекламы
enum AdPlacement: String, CaseIterable, Sendable {
    case dashboard
    case cards
    case debts
    case report
    case chat
}

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

    /// Размер баннера в пунктах. Он фиксированный, поэтому место под объявление занято сразу и экран не прыгает при загрузке
    static let bannerWidth: CGFloat = 320
    static let bannerHeight: CGFloat = 50

    /// Чаще запрашивать рекламу одного экрана нельзя: требования Рекламной сети Яндекса (не чаще раза в 30 секунд)
    static let minReloadInterval: TimeInterval = 30

    /// Можно ли сейчас запросить рекламу экрана, если прошлый запрос был в момент lastRequest
    static func canRequestAd(lastRequest: Date?, now: Date) -> Bool {
        guard let lastRequest else { return true }
        return now.timeIntervalSince(lastRequest) >= minReloadInterval
    }

    /// Где действует GDPR: страны ЕС (с внешними территориями), Исландия, Лихтенштейн, Норвегия, Великобритания и Швейцария
    static let gdprRegions: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT",
        "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
        "AX", "GF", "GP", "MF", "MQ", "RE", "YT",
        "IS", "LI", "NO", "GB", "CH"
    ]

    /// Жителям этих стран нужно согласие на обработку данных для рекламы; приложение его не спрашивает и передаёт отказ
    static func requiresGDPRConsent(regionCode: String?) -> Bool {
        guard let regionCode else { return false }
        return gdprRegions.contains(regionCode.uppercased())
    }

    /// Показывать ли рекламу сейчас: нужен блок, и это не режим снимков для App Store или ролика
    static func shouldShowAds(config: YandexAdsConfig, isScreenshotMode: Bool) -> Bool {
        config.isBannerEnabled && !isScreenshotMode
    }
}
