import AppTrackingTransparency
import SwiftUI
import YandexMobileAds

/// Баннер Яндекс Рекламы в конце экрана «Обзор», после последних операций. Это единственное место приложения,
/// которое знает про SDK Яндекса. В данные баннера не передаётся ничего из учёта: ни операции, ни карты, ни долги.
///
/// Без идентификатора блока (YandexAdsConfig) и в режимах снимков App Store ничего не показывает и не занимает места.
/// Порядок такой: приложение становится активным, iOS спрашивает разрешение на отслеживание (ATT), SDK инициализируется,
/// баннер создаётся один раз. Пока реклама не загрузилась (или не загрузится вовсе), баннер не занимает места.
@MainActor
struct AdBannerSection: View {
    @Environment(\.scenePhase) private var scenePhase

    private let unitID: String?

    /// Создаётся один раз: пересоздание при каждом обновлении экрана перезагружало бы рекламу
    @State private var bannerState: BannerState?
    @State private var isLoaded = false
    @State private var isPreparing = false

    init(config: YandexAdsConfig = .standard) {
        let isScreenshotMode = ScreenshotMode.scene != nil || ScreenshotMode.isTour
        unitID = YandexAdsConfig.shouldShowAds(config: config, isScreenshotMode: isScreenshotMode) ? config.bannerUnitID : nil
    }

    var body: some View {
        if let unitID {
            content(unitID: unitID)
        }
    }

    private func content(unitID: String) -> some View {
        VStack(spacing: 0) {
            // Невидимая опора для .task: у пустого контейнера жизненный цикл SwiftUI не срабатывает
            Color.clear
                .frame(height: 0)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await prepareBanner(unitID: unitID)
                }

            if let bannerState {
                Banner(state: bannerState)
                    .onAdLoad { _ in
                        isLoaded = true
                    }
                    .onAdFailure { _ in
                        isLoaded = false
                    }
                    // Высоту подбирает сам баннер после загрузки; до неё места он не занимает
                    .frame(height: isLoaded ? nil : 0)
                    .opacity(isLoaded ? 1 : 0)
                    .clipped()
            }
        }
        .padding(.top, isLoaded ? 20 : 0)
    }

    /// Спрашивает разрешение на отслеживание, запускает SDK и создаёт баннер. Повторные вызовы ничего не делают.
    private func prepareBanner(unitID: String) async {
        guard bannerState == nil, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        // Без ответа на этот запрос iOS не отдаёт рекламный идентификатор. Отказ рекламу не отключает: она просто менее персональная.
        _ = await ATTrackingManager.requestTrackingAuthorization()
        await YandexAds.initializeSDK()
        bannerState = BannerState(size: .sticky(), request: AdRequest(adUnitID: unitID))
    }
}
