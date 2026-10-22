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
    /// Подпись поверх ролика
    @State private var caption: String?

    func body(content: Content) -> some View {
        content
            .tourCaption(caption)
            .task {
                if ScreenshotMode.isTour {
                    await playTour()
                } else {
                    await prepare()
                }
            }
            .fullScreenCover(item: $cover) { scene in
                coverContent(scene)
                    .tourCaption(caption)
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

    private func show(_ text: String) {
        withAnimation(Motion.spring) {
            caption = text
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Сценарий около 27 секунд: обзор, листание карт, оформление карты, копилки, достижение цели, чат, отчёт.
    /// Экраны внутри (карусель, редактор, пополнение) играют свои части сами, когда `ScreenshotMode.isTour` истинно.
    private func playTour() async {
        DemoData.seed(financeService, forTour: true)
        selectedTab = .overview

        // Запись успевает начаться до первого кадра сценария; подпись видна с самого начала
        show(String(localized: "Весь учёт в одном месте"))
        await pause(8)

        withAnimation(Motion.spring) {
            selectedTab = .cards
        }
        show(String(localized: "Свои карты: листайте и настраивайте"))
        await pause(4.6)

        cover = .cardEditor
        show(String(localized: "Цвет, узор и значок: оформите карту по-своему"))
        await pause(4.6)

        cover = nil
        await pause(0.6)
        withAnimation(Motion.spring) {
            selectedTab = .overview
        }
        cover = .savings
        show(String(localized: "Копилки с планом накопления"))
        await pause(2.6)

        cover = nil
        await pause(0.7)
        cover = .goalMoney
        show(String(localized: "Цель достигнута!"))
        await pause(4.2)

        cover = nil
        await pause(0.6)
        let store = AIChatStore.shared
        store.reset()
        store.clearMessages()
        withAnimation(Motion.spring) {
            selectedTab = .assistant
        }
        show(String(localized: "СМС и скриншоты сами становятся операциями"))
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
        show(String(localized: "Отчёты по дням и категориям"))
        await pause(2.8)

        withAnimation(Motion.spring) {
            caption = nil
        }
    }
}

/// Подпись ролика: лаймовая плашка в полосе над экраном. Полоса занимает место, поэтому подпись не закрывает кнопки и списки.
/// Вне ролика ничего не добавляет.
private struct TourCaption: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if ScreenshotMode.isTour {
            content.safeAreaInset(edge: .top, spacing: 0) {
                ZStack {
                    if let text {
                        Text(text)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.onAccent)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                            .padding(.horizontal, 20)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .id(text)
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
    func tourCaption(_ text: String?) -> some View {
        modifier(TourCaption(text: text))
    }
}
#endif
