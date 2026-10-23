import SwiftUI

/// Экраны, которые снимаются для App Store
enum ScreenshotScene: String, CaseIterable, Identifiable {
    case overview
    case cards
    case cardEditor
    case savings
    case goal
    case chat
    case debts
    case report
    case settings
    /// Пополнение почти собранной копилки: только для ролика
    case goalMoney

    var id: String { rawValue }
}

/// Режим снимков и ролика для App Store. Только в отладочной сборке на симуляторе: запуск с аргументами
/// `-ScreenshotScene <имя>` и, для чата, `-ScreenshotQuestion <вопрос>` подставляет демонстрационные данные и открывает нужный экран;
/// `-ScreenshotTour` проигрывает сценарий ролика (App Preview).
/// В выпускной сборке (TestFlight, App Store) и на настоящем телефоне этого кода нет, `scene` пуст, а `isTour` ложно.
enum ScreenshotMode {
    static let scene: ScreenshotScene? = {
        #if DEBUG
        guard isSimulator else { return nil }
        return argument(after: "-ScreenshotScene").flatMap { ScreenshotScene(rawValue: $0) }
        #else
        return nil
        #endif
    }()

    /// Идёт ролик: экраны сами листаются и меняются по сценарию
    static let isTour: Bool = {
        #if DEBUG
        return isSimulator && ProcessInfo.processInfo.arguments.contains("-ScreenshotTour")
        #else
        return false
        #endif
    }()

    /// Вопрос, который задаётся чату на снимке
    static let question: String? = {
        #if DEBUG
        return argument(after: "-ScreenshotQuestion")
        #else
        return nil
        #endif
    }()

    #if DEBUG
    private static var isSimulator: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
    }

    private static func argument(after name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    #endif
}

extension View {
    /// Подключает режим снимков к главному экрану; в выпускной сборке ничего не меняет
    func screenshotScene(selectedTab: Binding<AppTab>, financeService: FinanceService) -> some View {
        #if DEBUG
        return modifier(ScreenshotSceneModifier(selectedTab: selectedTab, financeService: financeService))
        #else
        return self
        #endif
    }
}

#if DEBUG
@MainActor
private struct ScreenshotSceneModifier: ViewModifier {
    @Binding var selectedTab: AppTab
    let financeService: FinanceService
    @State private var cover: ScreenshotScene?
    /// Номер сцены ролика (0 — метки нет); по метке монтаж находит границы сцен
    @State private var scene = 0

    func body(content: Content) -> some View {
        content
            .tourMarker(scene)
            .task {
                if ScreenshotMode.isTour {
                    await playTour()
                } else {
                    await prepare()
                }
            }
            .fullScreenCover(item: $cover) { cover in
                coverContent(cover)
                    .tourMarker(scene)
            }
    }

    // MARK: - Снимки

    /// Подставляет данные, выбирает вкладку и, если нужно, открывает экран поверх неё
    private func prepare() async {
        guard let scene = ScreenshotMode.scene else { return }
        DemoData.seed(financeService)

        switch scene {
        case .overview, .savings, .goal, .settings, .goalMoney:
            selectedTab = .overview
        case .cards, .cardEditor:
            selectedTab = .cards
        case .chat:
            DemoData.fillChat()
            selectedTab = .assistant
        case .debts:
            selectedTab = .debts
        case .report:
            selectedTab = .report
        }

        switch scene {
        case .cardEditor, .savings, .goal, .settings:
            // Вкладка успевает показаться, и только потом поверх неё открывается экран
            try? await Task.sleep(for: .milliseconds(700))
            cover = scene
        default:
            break
        }
    }

    @ViewBuilder
    private func coverContent(_ scene: ScreenshotScene) -> some View {
        switch scene {
        case .cardEditor:
            CardEditorView(financeService: financeService, editing: financeService.cards.first)
        case .savings:
            SavingsView(financeService: financeService)
        case .goal:
            GoalDetailSheet(
                financeService: financeService,
                goalID: SavingsSummary.sortedActive(financeService.goals).first?.id ?? UUID()
            )
        case .settings:
            SettingsView(financeService: financeService)
        case .goalMoney:
            GoalMoneySheet(
                financeService: financeService,
                goalID: DemoData.nearlyDoneGoal(in: financeService)?.id ?? UUID(),
                mode: .deposit
            )
        default:
            EmptyView()
        }
    }

    // MARK: - Ролик

    private func mark(_ number: Int) {
        scene = number
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Сценарий около 33 секунд: обзор, листание карт, оформление карты, копилки, достижение цели, чат, отчёт.
    /// Экраны внутри (карусель, редактор, пополнение) играют свои части сами, когда `ScreenshotMode.isTour` истинно.
    /// Подписи в запись не попадают: каждая сцена получает номер (1-7), а готовый ролик собирает Tools/AppPreview
    /// и рисует над номером свою анимированную подпись: «Весь учёт в одном месте», «Свои карты…», «Цвет, узор и значок…»,
    /// «Копилки с планом накопления», «Цель достигнута!», «СМС и скриншоты сами становятся операциями», «Отчёты по дням и категориям».
    private func playTour() async {
        DemoData.seed(financeService, forTour: true)
        selectedTab = .overview

        // Запись успевает начаться до первого кадра сценария; метка видна с самого начала
        mark(1)
        await pause(8)

        withAnimation(Motion.spring) {
            selectedTab = .cards
        }
        mark(2)
        await pause(4.6)

        cover = .cardEditor
        mark(3)
        await pause(4.6)

        cover = nil
        await pause(0.6)
        withAnimation(Motion.spring) {
            selectedTab = .overview
        }
        cover = .savings
        mark(4)
        await pause(2.6)

        cover = nil
        await pause(0.7)
        cover = .goalMoney
        mark(5)
        await pause(4.2)

        cover = nil
        await pause(0.6)
        let store = AIChatStore.shared
        store.reset()
        store.clearMessages()
        withAnimation(Motion.spring) {
            selectedTab = .assistant
        }
        mark(6)
        await pause(0.8)
        store.send(text: DemoData.sampleSMS())
        await pause(1.8)
        if let question = ScreenshotMode.question {
            store.send(text: question)
        }
        await pause(1.6)

        withAnimation(Motion.spring) {
            selectedTab = .report
        }
        mark(7)
        await pause(2.8)

        mark(0)
    }
}

/// Метка сцены ролика: тонкая серая полоска в полосе над экраном, длина полоски равна номеру сцены (24 пункта на номер).
/// Подписи рисует монтаж (Tools/AppPreview), по метке он находит, какая сцена идёт, и закрашивает полосу.
/// Полоса занимает место, поэтому экраны внутри выглядят так же, как с подписью. Вне ролика ничего не добавляет.
private struct TourMarker: ViewModifier {
    let scene: Int

    func body(content: Content) -> some View {
        if ScreenshotMode.isTour {
            content.safeAreaInset(edge: .top, spacing: 0) {
                ZStack(alignment: .leading) {
                    Color.clear
                    if scene > 0 {
                        Rectangle()
                            .fill(Color(white: 0.6))
                            .frame(width: 24 * CGFloat(scene), height: 4)
                            .padding(.leading, 16)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 78)
                .background(Theme.background)
                .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

private extension View {
    func tourMarker(_ scene: Int) -> some View {
        modifier(TourMarker(scene: scene))
    }
}
#endif
