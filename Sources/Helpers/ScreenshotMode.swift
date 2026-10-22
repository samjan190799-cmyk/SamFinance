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

    var id: String { rawValue }
}

/// Режим снимков для App Store. Только в отладочной сборке на симуляторе: запуск с аргументами
/// `-ScreenshotScene <имя>` и, для чата, `-ScreenshotQuestion <вопрос>` подставляет демонстрационные данные и открывает нужный экран.
/// В выпускной сборке (TestFlight, App Store) и на настоящем телефоне этого кода нет, `scene` всегда пуст.
enum ScreenshotMode {
    static let scene: ScreenshotScene? = {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil else { return nil }
        return argument(after: "-ScreenshotScene").flatMap { ScreenshotScene(rawValue: $0) }
        #else
        return nil
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

    func body(content: Content) -> some View {
        content
            .task {
                await prepare()
            }
            .fullScreenCover(item: $cover) { scene in
                coverContent(scene)
            }
    }

    /// Подставляет данные, выбирает вкладку и, если нужно, открывает экран поверх неё
    private func prepare() async {
        guard let scene = ScreenshotMode.scene else { return }
        DemoData.seed(financeService)

        switch scene {
        case .overview, .savings, .goal, .settings:
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
        default:
            EmptyView()
        }
    }
}
#endif
