import XCTest
@testable import SamFinance

/// Полоса под строкой состояния: высота должна быть заметно больше самой высокой строки состояния
/// (iPhone с островком около 60 pt). Прежняя версия брала высоту из GeometryReader и на устройстве получалась нулевой.
@MainActor
final class StatusBarCoverTests: XCTestCase {
    func testCoverIsTallerThanAnyStatusBar() {
        XCTAssertGreaterThanOrEqual(StatusBarCover.height, 120)
    }
}
