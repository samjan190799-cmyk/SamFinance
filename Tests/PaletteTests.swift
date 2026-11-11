import XCTest
@testable import SamFinance

/// Разноцветная палитра «Пульса»: цвета категорий различимы, лайм остаётся за брендом, тёмный текст поверх цвета читается
final class PaletteTests: XCTestCase {

    func testEveryPaletteColorIsLightEnoughForDarkText() {
        for color in PaletteColor.allCases {
            XCTAssertTrue(Theme.isLight(hex: color.rawValue), "\(color): поверх него пишется тёмный текст, цвет должен быть светлым")
        }
    }

    func testBrandLimeIsNotInThePalette() {
        let accentHex = "#C6F432"
        XCTAssertFalse(PaletteColor.allCases.map(\.rawValue).contains(accentHex), "лайм — цвет бренда, у категорий его быть не должно")
    }

    func testBuiltInExpenseCategoriesHaveDistinctColors() {
        // В кольце долей и в плитках категорий у разных трат не должно быть одинаковых цветов
        let names = Set(Category.defaultCategories.filter { $0.type == .expense }.map(\.name))
        let colors = Set(names.map { PaletteColor.forCategory(named: $0) })
        XCTAssertEqual(colors.count, names.count)
    }

    func testCustomCategoryColorIsStableAndComesFromTheRotation() {
        let coffee = PaletteColor.forCategory(named: "Кофе")
        XCTAssertEqual(coffee, PaletteColor.forCategory(named: "Кофе"), "цвет не должен меняться между вызовами и запусками")
        XCTAssertTrue(PaletteColor.rotation.contains(coffee))
        XCTAssertTrue(PaletteColor.rotation.contains(PaletteColor.forCategory(named: "")))
    }

    func testBuiltInCategoriesUseExistingSymbols() {
        for category in Category.defaultCategories {
            XCTAssertEqual(category.badgeSymbol, category.icon, "\(category.name): значка \(category.icon) нет в SF Symbols")
        }
    }

    func testUnknownSymbolFallsBackToTag() {
        let custom = Category(name: "Кофе", icon: "no.such.symbol.hashiv", colorHex: "#000000", type: .expense)
        XCTAssertEqual(custom.badgeSymbol, "tag.fill")
    }
}
