import AppTrackingTransparency
import SwiftUI
import YandexMobileAds

/// Баннер Яндекс Рекламы. У каждой из пяти вкладок свой баннер: он стоит внутри прокрутки между первым и вторым блоком
/// экрана (на «Обзоре» между картой баланса и кнопками) и прокручивается вместе с содержимым.
/// Это единственное место приложения, которое знает про SDK Яндекса.
/// В данные баннера не передаётся ничего из учёта: ни операции, ни карты, ни долги.
///
/// Требования Рекламной сети Яндекса к рекламе в приложениях, которые держит этот вид:
/// - место под баннер (320×50) занято с самого начала, поэтому объявление не появляется неожиданно и не сдвигает кнопки;
/// - над и под баннером отступ `verticalSpacing`: кнопки не стоят вплотную к объявлению, ничто его не перекрывает;
/// - один экран запрашивает рекламу не чаще раза в 30 секунд (`AdsRuntime`): при более быстром возвращении на вкладку
///   баннера на ней нет;
/// - после ошибки загрузки повторного запроса нет, пустое место убирается.
///
/// Без идентификатора блока (YandexAdsConfig) и в режимах снимков App Store ничего не показывает и не занимает места.
/// Порядок такой: приложение становится активным, iOS спрашивает разрешение на отслеживание (ATT), для жителей ЕЭЗ,
/// Великобритании и Швейцарии передаётся отказ от согласия (GDPR), SDK инициализируется, баннер запрашивает рекламу.
@MainActor
struct AdBannerSection: View {
    /// Отступ сверху и снизу, пока под баннер держится место: до соседних блоков и кнопок экрана
    static let verticalSpacing: CGFloat = 20

    @Environment(\.scenePhase) private var scenePhase

    private let placement: AdPlacement
    private let unitID: String?
    private let showsErrors: Bool

    /// Решается один раз, когда вид появляется: рекламу этого экрана нельзя запрашивать чаще раза в 30 секунд
    @State private var isAllowed: Bool
    /// Создаётся один раз на экземпляр баннера: пересоздание при каждом обновлении экрана перезагружало бы рекламу
    @State private var bannerState: BannerState?
    @State private var isLoaded = false
    @State private var isFailed = false
    @State private var isPreparing = false
    /// Стадия и ошибка баннера; заполняется и показывается только в проверочной сборке (YandexAdsConfig.showsErrors)
    @State private var debugLine = ""

    init(placement: AdPlacement, config: YandexAdsConfig = .standard) {
        let isScreenshotMode = ScreenshotMode.scene != nil || ScreenshotMode.isTour
        self.placement = placement
        unitID = YandexAdsConfig.shouldShowAds(config: config, isScreenshotMode: isScreenshotMode) ? config.bannerUnitID : nil
        showsErrors = config.showsErrors
        _isAllowed = State(initialValue: AdsRuntime.canRequest(placement))
    }

    var body: some View {
        if let unitID {
            if isAllowed {
                content(unitID: unitID)
            } else if showsErrors {
                debugText("throttled: \(placement.rawValue) asked less than 30 s ago")
            }
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

            if !isFailed {
                // Место под объявление держится всё время загрузки: экран не прыгает, когда баннер появляется
                ZStack {
                    if let bannerState {
                        Banner(state: bannerState)
                            .onAdLoad { _ in
                                isLoaded = true
                                note("loaded")
                            }
                            .onAdFailure { error in
                                // Неудачное обновление уже показанного объявления его не убирает
                                if !isLoaded {
                                    isFailed = true
                                }
                                note("FAILED: \(String(describing: error))")
                            }
                            .opacity(isLoaded ? 1 : 0)
                    }
                }
                .frame(width: YandexAdsConfig.bannerWidth, height: YandexAdsConfig.bannerHeight)
                .clipped()
            }

            // Только проверочная сборка: на каком шаге остановилась реклама и что ответил Яндекс
            if showsErrors, !debugLine.isEmpty {
                debugText(debugLine)
            }
        }
        .padding(.vertical, isFailed ? 0 : Self.verticalSpacing)
        .frame(maxWidth: .infinity)
    }

    private func debugText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(Theme.textSecondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }

    /// Ждёт запуска SDK и создаёт баннер. Повторные вызовы ничего не делают.
    private func prepareBanner(unitID: String) async {
        guard bannerState == nil, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        note("SDK init...")
        await AdsRuntime.prepare()
        // Пока шёл запуск SDK, этот экран уже мог запросить рекламу другим экземпляром баннера
        guard AdsRuntime.canRequest(placement) else {
            isAllowed = false
            return
        }
        AdsRuntime.registerRequest(placement)
        note("SDK ready, request sent, unit \(unitID)")
        // Размер совпадает с YandexAdsConfig.bannerWidth и bannerHeight
        bannerState = BannerState(size: .fixed(width: 320, height: 50), request: AdRequest(adUnitID: unitID))
    }

    private func note(_ text: String) {
        if showsErrors {
            debugLine = text
        }
    }
}

/// Запрос ATT и запуск SDK Яндекса: один раз за запуск приложения. Здесь же запоминается, когда каждый экран
/// в последний раз запрашивал рекламу.
/// Запуск идёт в отдельной задаче: когда iOS показывает окно ATT, приложение на миг неактивно, и задача баннера
/// (`.task(id: scenePhase)`) отменяется, а запрос должен дойти до конца.
@MainActor
private enum AdsRuntime {
    private static var preparation: Task<Void, Never>?
    private static var lastRequests: [AdPlacement: Date] = [:]

    static func canRequest(_ placement: AdPlacement, now: Date = Date()) -> Bool {
        YandexAdsConfig.canRequestAd(lastRequest: lastRequests[placement], now: now)
    }

    static func registerRequest(_ placement: AdPlacement, now: Date = Date()) {
        lastRequests[placement] = now
    }

    static func prepare() async {
        let task: Task<Void, Never> = preparation ?? Task { @MainActor in
            // Без ответа на этот запрос iOS не отдаёт рекламный идентификатор. Отказ рекламу не отключает: она просто менее персональная.
            _ = await ATTrackingManager.requestTrackingAuthorization()
            // GDPR: согласие приложение не спрашивает, поэтому жителям этих стран передаётся отказ. Значение нужно при каждом запуске.
            if YandexAdsConfig.requiresGDPRConsent(regionCode: Locale.current.region?.identifier) {
                YandexAds.setUserConsent(false)
            }
            await YandexAds.initializeSDK()
        }
        preparation = task
        await task.value
    }
}
