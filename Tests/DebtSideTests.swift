import XCTest
@testable import SamFinance

/// Вкладки долгов «Мне должны» и «Я должен»: каждый долг лежит ровно на одной стороне
final class DebtSideTests: XCTestCase {
    private func debt(isLent: Bool, type: DebtType = .person, isPaid: Bool = false) -> Debt {
        Debt(name: "Тест", amount: 1_000, isLent: isLent, isPaid: isPaid, type: type)
    }

    func testPeopleAreSplitByDirection() {
        let lent = debt(isLent: true)
        let borrowed = debt(isLent: false)
        XCTAssertTrue(DebtSide.owedToMe.contains(lent))
        XCTAssertFalse(DebtSide.iOwe.contains(lent))
        XCTAssertTrue(DebtSide.iOwe.contains(borrowed))
        XCTAssertFalse(DebtSide.owedToMe.contains(borrowed))
    }

    func testCreditsAreOnTheSideWhereIOwe() {
        let credit = debt(isLent: false, type: .credit)
        XCTAssertEqual(DebtSide(debt: credit), .iOwe)
        XCTAssertTrue(DebtSide.iOwe.contains(credit))
        XCTAssertFalse(DebtSide.owedToMe.contains(credit))
    }

    func testEveryDebtBelongsToExactlyOneSide() {
        let debts = [
            debt(isLent: true), debt(isLent: false), debt(isLent: false, type: .credit),
            debt(isLent: true, isPaid: true), debt(isLent: false, isPaid: true)
        ]
        for debt in debts {
            XCTAssertEqual(DebtSide.allCases.filter { $0.contains(debt) }.count, 1)
        }
    }

    func testTabsAreTitledAndOrderedLikeTheTotals() {
        XCTAssertEqual(DebtSide.allCases, [.owedToMe, .iOwe])
        XCTAssertEqual(DebtSide.owedToMe.title, String(localized: "Мне должны"))
        XCTAssertEqual(DebtSide.iOwe.title, String(localized: "Я должен"))
    }
}
