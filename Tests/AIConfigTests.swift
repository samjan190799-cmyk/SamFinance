import XCTest
@testable import SamFinance

/// Ключ, сервис и модель ИИ задаёт сборка: разбор Info.plist и выбор ключа
final class AIConfigTests: XCTestCase {

    func testValuesAreReadFromTheInfoDictionary() {
        let config = AIConfig(info: ["AIAPIKey": "  secret-key  ", "AIProviderName": "OpenAI", "AIModelName": " gpt-x "])
        XCTAssertEqual(config.apiKey, "secret-key")
        XCTAssertEqual(config.provider, .openAI)
        XCTAssertEqual(config.modelName, "gpt-x")
    }

    func testProviderNameIsCaseInsensitive() {
        XCTAssertEqual(AIConfig(info: ["AIProviderName": "CLAUDE"]).provider, .claude)
        XCTAssertEqual(AIConfig(info: ["AIProviderName": "Gemini"]).provider, .gemini)
        XCTAssertEqual(AIConfig(info: ["AIProviderName": "openai"]).provider, .openAI)
    }

    func testMissingEmptyAndUnsubstitutedValuesMeanNone() {
        for info in [
            [String: Any](),
            ["AIAPIKey": "", "AIProviderName": "", "AIModelName": ""],
            ["AIAPIKey": "   ", "AIProviderName": "\n", "AIModelName": " "],
            // Переменная сборки, которую никто не подставил, остаётся в Info.plist буквально
            ["AIAPIKey": "$(AI_API_KEY)", "AIProviderName": "$(AI_PROVIDER)", "AIModelName": "$(AI_MODEL)"]
        ] {
            let config = AIConfig(info: info)
            XCTAssertNil(config.apiKey, "\(info)")
            XCTAssertNil(config.modelName, "\(info)")
            XCTAssertEqual(config.provider, .gemini, "без названия сервис по умолчанию Gemini: \(info)")
        }
    }

    func testUnknownProviderFallsBackToGemini() {
        XCTAssertEqual(AIConfig(info: ["AIProviderName": "skynet"]).provider, .gemini)
    }

    func testValuesOfTheWrongTypeAreIgnored() {
        let config = AIConfig(info: ["AIAPIKey": 12345, "AIProviderName": ["claude"], "AIModelName": true])
        XCTAssertNil(config.apiKey)
        XCTAssertNil(config.modelName)
        XCTAssertEqual(config.provider, .gemini)
    }

    // MARK: - Ключ

    func testKeyBelongsOnlyToTheConfiguredProvider() {
        let config = AIConfig(apiKey: "the-key", provider: .gemini)
        XCTAssertEqual(AIKeyStore.key(for: .gemini, config: config), "the-key")
        XCTAssertNil(AIKeyStore.key(for: .claude, config: config), "ключ Gemini нельзя отправлять другому сервису")
        XCTAssertNil(AIKeyStore.key(for: .openAI, config: config))
    }

    func testBuildWithoutKeyHasNoKeyForAnyone() {
        let config = AIConfig(apiKey: nil, provider: .claude)
        for provider in AIProvider.allCases {
            XCTAssertNil(AIKeyStore.key(for: provider, config: config), provider.rawValue)
        }
    }

    func testRemovingLegacyKeysIsSafeToRepeat() {
        AIKeyStore.removeLegacyKeys()
        AIKeyStore.removeLegacyKeys()
    }

    // MARK: - Info.plist приложения

    func testAppInfoPlistHasTheSlotsTheBuildFills() throws {
        // Шаг «Inject AI Settings» в testflight.yml делает Set по этим ключам: их отсутствие сломало бы сборку для TestFlight
        let info = try XCTUnwrap(Bundle(for: FinanceService.self).infoDictionary)
        for key in [AIConfig.InfoKey.apiKey, AIConfig.InfoKey.provider, AIConfig.InfoKey.model] {
            XCTAssertTrue(info[key] is String, "в Info.plist нет ключа \(key): проверьте info.properties в project.yml")
        }
    }
}
