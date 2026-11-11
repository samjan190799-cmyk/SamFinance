import AppTrackingTransparency
import SwiftUI
import YandexMobileAds

/// Баннер Яндекс Рекламы. У каждой из пяти вкладок свой баннер: ContentView создаёт его заново при смене вкладки
/// (`.id(selectedTab)`), и он закреплён вверху экрана над содержимым вкладки, поэтому виден при любой прокрутке.
/// Это единственное место приложения, которое знает про SDK Яндекса.
/// В данные баннера не передаётся ничего из учёта: ни операции, ни карты, ни долги.
///
/// Без идентификатора блока (YandexAdsConfig) и в режимах снимков App Store ничего не показывает и не занимает места.
/// Порядок такой: приложение становится активным, iOS спрашивает разрешение на отслеживание (ATT), SDK инициализируется
/// (см. AdsRuntime), баннер вкладки запрашивает рекламу. Пока она не загрузилась, место под баннер остаётся таким же, как
/// у прошлого: иначе экран прыгал бы вверх-вниз при каждой смене вкладки. Если реклама не загрузилась, баннер уходит.
@MainActor
struct AdBannerSection: View {
    /// Отступ сверху и снизу, пока баннер показан: сверху до строки состояния, снизу до заголовка раздела
    static let verticalSpacing: CGFloat = 6

    @Environment(\.scenePhase) private var scenePhase

    private let unitID: String?

    /// Создаётся один раз на экземпляр баннера: пересоздание при каждом обновлении экрана перезагружало бы рекламу
    @State private var bannerState: BannerState?
    @State private var isLoaded = false
    @State private var isFailed = false
    @State private var isPreparing = false

    init(config: YandexAdsConfig = .standard) {
        let isScreenshotMode = ScreenshotMode.scene != nil || ScreenshotMode.isTour
        unitID = YandexAdsConfig.shouldShowAds(config: config, isScreenshotMode: isScreenshotMode) ? config.bannerUnitID : nil
    }

    /// Сколько места держать под баннером, пока реклама грузится: высоту прошлого баннера. Загрузился или не загрузился,
    /// держать нечего: загруженный сам занимает своё место, а у незагрузившегося места быть не должно.
    static func reservedHeight(isLoaded: Bool, isFailed: Bool, lastHeight: CGFloat) -> CGFloat {
        isLoaded || isFailed ? 0 : lastHeight
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
                        isFailed = false
                    }
                    .onAdFailure { _ in
                        isLoaded = false
                        isFailed = true
                    }
                    // Высоту подбирает сам баннер после загрузки; до неё места он не занимает
                    .frame(height: isLoaded ? nil : 0)
                    .opacity(isLoaded ? 1 : 0)
                    .clipped()
            }
        }
        .padding(.vertical, isLoaded ? Self.verticalSpacing : 0)
        .frame(minHeight: Self.reservedHeight(isLoaded: isLoaded, isFailed: isFailed, lastHeight: AdsRuntime.lastStripHeight), alignment: .top)
        .frame(maxWidth: .infinity)
        // Сплошной фон: когда баннер закреплён над прокруткой, она не должна просвечивать за ним
        .background(isLoaded ? Theme.background : Color.clear)
        // Высота загруженной полосы запоминается для следующей вкладки
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            if isLoaded, height > 0 {
                AdsRuntime.lastStripHeight = height
            }
        }
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

/// Запрос ATT и запуск SDK Яндекса: один раз за запуск приложения. Здесь же запоминается высота последнего загруженного баннера.
/// Работа идёт в отдельной задаче: когда iOS показывает окно ATT, приложение на миг неактивно, и задача баннера
/// (`.task(id: scenePhase)`) отменяется, а запрос должен дойти до конца.
@MainActor
private enum AdsRuntime {
    private static var preparation: Task<Void, Never>?

    /// Высота полосы последнего загруженного баннера (сам баннер и отступы); 0, пока ни один не загрузился
    static var lastStripHeight: CGFloat = 0

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
