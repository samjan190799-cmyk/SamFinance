import XCTest
@testable import SamFinance

/// Реклама Яндекса: идентификатор блока задаёт сборка; всё, без чего App Store или iOS отклонят рекламу, лежит в Info.plist
final class YandexAdsConfigTests: XCTestCase {

    private let appBundle = Bundle(for: FinanceService.self)

    // MARK: - Разбор настроек

    func testUnitIDIsReadAndTrimmed() {
        let config = YandexAdsConfig(info: ["YandexAdsBannerUnitID": "  R-M-123456-1  "])
        XCTAssertEqual(config.bannerUnitID, "R-M-123456-1")
        XCTAssertTrue(config.isBannerEnabled)
    }

    func testMissingEmptyAndUnsubstitutedValuesMeanNoAds() {
        let cases: [[String: Any]] = [
            [:],
            ["YandexAdsBannerUnitID": ""],
            ["YandexAdsBannerUnitID": "   \n"],
            // Переменная сборки, которую никто не подставил, остаётся в Info.plist буквально
            ["YandexAdsBannerUnitID": "$(YANDEX_ADS_BANNER_ID)"]
        ]
        for info in cases {
            let config = YandexAdsConfig(info: info)
            XCTAssertNil(config.bannerUnitID, "\(info)")
            XCTAssertFalse(config.isBannerEnabled, "\(info)")
        }
    }

    func testValueOfTheWrongTypeMeansNoAds() {
        XCTAssertNil(YandexAdsConfig(info: ["YandexAdsBannerUnitID": 123456]).bannerUnitID)
        XCTAssertNil(YandexAdsConfig(info: ["YandexAdsBannerUnitID": ["R-M-1-1"]]).bannerUnitID)
    }

    func testAdsNeedAUnitIDAndNeverShowInScreenshotModes() {
        let enabled = YandexAdsConfig(bannerUnitID: "R-M-123456-1")
        let disabled = YandexAdsConfig(bannerUnitID: nil)
        XCTAssertTrue(YandexAdsConfig.shouldShowAds(config: enabled, isScreenshotMode: false))
        XCTAssertFalse(YandexAdsConfig.shouldShowAds(config: enabled, isScreenshotMode: true), "в снимках App Store рекламы нет")
        XCTAssertFalse(YandexAdsConfig.shouldShowAds(config: disabled, isScreenshotMode: false))
        XCTAssertFalse(YandexAdsConfig.shouldShowAds(config: disabled, isScreenshotMode: true))
    }

    func testDemoUnitIDIsTheOneFromTheYandexDocs() {
        XCTAssertEqual(YandexAdsConfig.demoBannerUnitID, "demo-banner-yandex")
        XCTAssertTrue(YandexAdsConfig(bannerUnitID: YandexAdsConfig.demoBannerUnitID).isBannerEnabled)
    }

    func testTheRepositoryNeverShipsAUnitID() {
        // Идентификатор блока приходит только из секрета GitHub при сборке. Если он оказался в project.yml, этот тест упадёт.
        XCTAssertFalse(YandexAdsConfig.standard.isBannerEnabled, "в Info.plist из репозитория должен быть пустой идентификатор блока")
    }

    @MainActor
    func testBuildsWithoutAUnitIDHaveNoAdPlacement() {
        // Списку долгов баннер нужен отдельной строкой; без идентификатора блока строки быть не должно
        XCTAssertFalse(AdBannerSection.isAvailable)
    }

    // MARK: - Info.plist приложения

    func testAppInfoPlistHasTheAdsSlotAndTheKeysAdsNeed() throws {
        let info = try XCTUnwrap(appBundle.infoDictionary)
        // Шаг «Inject Ads Settings» в testflight.yml делает Add по этому ключу и проверяет остальные
        XCTAssertTrue(info[YandexAdsConfig.InfoKey.bannerUnitID] is String, "нет ключа YandexAdsBannerUnitID: проверьте info.properties в project.yml")

        let tracking = info["NSUserTrackingUsageDescription"] as? String
        XCTAssertFalse((tracking ?? "").isEmpty, "без текста запроса отслеживания iOS завершит приложение при запросе ATT")

        let items = try XCTUnwrap(info["SKAdNetworkItems"] as? [[String: String]], "нет списка SKAdNetwork")
        let identifiers = items.compactMap { $0["SKAdNetworkIdentifier"] }
        XCTAssertGreaterThan(identifiers.count, 100)
        XCTAssertTrue(identifiers.contains("zq492l623r.skadnetwork"), "нет идентификатора самого Яндекса")
        XCTAssertTrue(identifiers.allSatisfy { $0.hasSuffix(".skadnetwork") })
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "в списке SKAdNetwork есть повторы")
    }

    func testTrackingRequestTextIsTranslatedInEveryLanguage() throws {
        let cyrillic = try NSRegularExpression(pattern: "[А-Яа-яЁё]")
        for language in ["ru", "en", "hy"] {
            let path = try XCTUnwrap(
                appBundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: language),
                "нет InfoPlist.strings для \(language)"
            )
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], "не читается InfoPlist.strings для \(language)")
            let text = try XCTUnwrap(table["NSUserTrackingUsageDescription"], language)
            XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, language)
            if language != "ru" {
                XCTAssertNil(cyrillic.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), "русские буквы в переводе \(language)")
            }
        }
    }

    // MARK: - Манифест приватности

    func testPrivacyManifestDeclaresTheTrackingThatAdsDo() throws {
        let url = try XCTUnwrap(appBundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"), "манифест приватности не попал в приложение")
        let manifest = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, true, "реклама отслеживает: без этого App Store отклонит сборку с запросом ATT")

        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let forAds = collected.filter { item in
            (item["NSPrivacyCollectedDataTypePurposes"] as? [String])?.contains("NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising") == true
        }
        let adTypes = Set(forAds.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        XCTAssertTrue(adTypes.contains("NSPrivacyCollectedDataTypeDeviceID"), "\(adTypes)")
        XCTAssertTrue(adTypes.contains("NSPrivacyCollectedDataTypeAdvertisingData"), "\(adTypes)")
        XCTAssertTrue(forAds.allSatisfy { $0["NSPrivacyCollectedDataTypeTracking"] as? Bool == true })

        // Прежние пункты про финансовые данные остаются: они только для работы приложения и не для рекламы
        let financial = collected.first { $0["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypeOtherFinancialInfo" }
        XCTAssertEqual(financial?["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        XCTAssertEqual(financial?["NSPrivacyCollectedDataTypePurposes"] as? [String], ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
    }
}
