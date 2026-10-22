#if DEBUG
import XCTest
@testable import SamFinance

/// Демонстрационные данные для снимков App Store должны выглядеть спокойно и работать со сценами
@MainActor
final class DemoDataTests: XCTestCase {
    private var service: FinanceService { FinanceService.shared }

    // Вызов super.setUp() здесь не нужен (он пустой) и не компилируется в Swift 6 для MainActor-классов
    override func setUp() async throws {
        service.resetAllData()
    }

    override func tearDown() async throws {
        service.resetAllData()
        AIChatStore.shared.reset()
    }

    func testSeedFillsEveryScreen() {
        DemoData.seed(service)
        XCTAssertEqual(service.cards.count, 3)
        XCTAssertGreaterThanOrEqual(service.transactions.count, 20)
        XCTAssertGreaterThanOrEqual(service.debts.count, 3)
        XCTAssertTrue(service.debts.contains { $0.type == .credit })
        XCTAssertTrue(service.debts.contains { $0.type == .person })
        XCTAssertEqual(service.goals.count, 3)
        XCTAssertTrue(service.cards.allSatisfy { $0.pattern != nil && $0.network != nil })
    }

    func testRecentDaysHaveSpendingForTheWeekChart() {
        DemoData.seed(service)
        let weekExpenses = service.transactions.filter { $0.type == .expense && TimePeriodFilter.week.contains($0.date) }
        XCTAssertGreaterThanOrEqual(weekExpenses.count, 8)
        // Новые операции идут в начале списка
        XCTAssertEqual(service.transactions.first?.id, service.transactions.max { $0.date < $1.date }?.id)
    }

    func testGoalsAreOnTrack() {
        DemoData.seed(service)
        for goal in service.goals {
            let plan = GoalPlan(goal: goal)
            XCTAssertEqual(plan.status, .onTrack, goal.title)
            XCTAssertNotNil(goal.cardId)
            XCTAssertEqual(goal.entries.reduce(0.0) { $0 + $1.amount }, goal.currentAmount, accuracy: 0.001, goal.title)
        }
    }

    func testSampleSMSIsRecognizedAsAGroceryPurchase() throws {
        let parsed = try XCTUnwrap(SMSParser.parse(text: DemoData.sampleSMS()))
        XCTAssertEqual(parsed.amount, 18_400, accuracy: 0.001)
        XCTAssertEqual(parsed.cardLast4, "4821")
        XCTAssertEqual(parsed.categoryName, "Продукты")
        XCTAssertNotNil(parsed.date)
    }

    func testChatSceneLeavesADraftAndAnAnswer() {
        DemoData.seed(service)
        AIChatStore.shared.reset()
        AIChatStore.shared.send(text: DemoData.sampleSMS())
        AIChatStore.shared.send(text: "how much did I spend this week?")

        let messages = AIChatStore.shared.messages
        XCTAssertTrue(messages.contains { $0.draft != nil })
        XCTAssertEqual(messages.last?.role, .assistant)
        XCTAssertNotEqual(messages.last?.text, LocalFinanceAssistant.helpText)
    }

    func testScreenshotModeIsOffInTests() {
        XCTAssertNil(ScreenshotMode.scene)
    }
}
#endif
