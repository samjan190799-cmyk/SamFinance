import XCTest
@testable import SamFinance

/// Действия Hashiv для «Быстрых команд»: без списка быстрых команд приложение не находится в их поиске
final class HashivShortcutsTests: XCTestCase {
    func testBothActionsAreExposedToShortcuts() {
        XCTAssertEqual(HashivShortcuts.appShortcuts.count, 2)
    }
}
