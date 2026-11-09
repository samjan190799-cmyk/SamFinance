import AppTrackingTransparency
import SwiftUI
import YandexMobileAds

/// Баннер Яндекс Рекламы: один на всё приложение, закреплён вверху экрана над разделами (ContentView) и виден на любом
/// из них, как бы далеко ни прокрутили содержимое. Это единственное место приложения, которое знает про SDK Яндекса.
/// В данные баннера не передаётся ничего из учёта: ни операции, ни карты, ни долги.
///
/// Без идентификатора блока (YandexAdsConfig) и в режимах снимков App Store ничего не показывает и не занимает места.
/// Порядок такой: приложение становится активным, iOS спрашивает разрешение на отслеживание (ATT), SDK инициализируется
/// (см. AdsRuntime), баннер создаётся один раз. Смена раздела его не пересоздаёт, поэтому реклама не запрашивается заново
/// при каждом переходе. Пока реклама не загрузилась (или не загрузится вовсе), баннер не занимает места.
@MainActor
struct AdBannerSection: View {
    /// Отступ сверху и снизу, пока баннер показан: сверху до строки состояния, снизу до заголовка раздела
    static let verticalSpacing: CGFloat = 6

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
        .padding(.vertical, isLoaded ? Self.verticalSpacing : 0)
        .frame(maxWidth: .infinity)
        // Сплошной фон: когда баннер закреплён над прокруткой, она не должна просвечивать за ним
        .background(isLoaded ? Theme.background : Color.clear)
    }

    /// Ждёт запуска SDK и создаёт баннер. Повторные вызовы ничего не делают.
    private func prepareBanner(unitID: String) async {
        guard bannerState == nil, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        await AdsRuntime.prepare()
        bannerState = BannerState(size: .sticky(), request: AdRequest(adUnitID: unitID))
    }
}

/// Запрос ATT и запуск SDK Яндекса: один раз за запуск приложения.
/// Работа идёт в отдельной задаче: когда iOS показывает окно ATT, приложение на миг неактивно, и задача баннера
/// (`.task(id: scenePhase)`) отменяется, а запрос должен дойти до конца.
@MainActor
private enum AdsRuntime {
    private static var preparation: Task<Void, Never>?

    static func prepare() async {
        let task: Task<Void, Never> = preparation ?? Task { @MainActor in
            // Без ответа на этот запрос iOS не отдаёт рекламный идентификатор. Отказ рекламу не отключает: она просто менее персональная.
            _ = await ATTrackingManager.requestTrackingAuthorization()
            await YandexAds.initializeSDK()
        }
        preparation = task
        await task.value
    }
}
