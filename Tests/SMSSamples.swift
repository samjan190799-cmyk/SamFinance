import Foundation
@testable import SamFinance

/// `Category` из приложения; без модуля это имя конфликтует с типом Category из Objective-C
typealias AppCategory = SamFinance.Category

/// Примеры банковских СМС для тестов. Даты в прошлом, чтобы разбор не отсёк их как «из будущего».
enum SMSSamples {
    /// Покупка в магазине: сумма, маска карты, магазин, дата и остаток
    static let groceryPurchase = """
    GNUM
    3,500.00 AMD
    4318***0640
    SAS SUPERMARKET, AM
    15.01.2025 14:32
    MNACORD 120,000.00
    """

    /// Зачисление зарплаты
    static let salary = """
    MUTQ
    150,000.00 AMD
    4318***0640
    SALARY CO, AM
    10.01.2025 11:02
    MNACORD 270,000.00
    """

    /// Исходящий перевод с карты на карту
    static let transferOut = """
    C2C
    10,000.00 AMD
    4318***0640
    TO: ARMEN PETROSYAN, AM
    12.01.2025 09:10
    MNACORD 100,000.00
    """

    /// Входящий перевод
    static let transferIn = """
    C2C
    25,000.00 AMD
    4318***0640
    FROM: ARMEN PETROSYAN, AM
    13.01.2025 18:40
    MNACORD 125,000.00
    """

    /// Снятие наличных в банкомате
    static let atmWithdrawal = """
    ATM
    20,000.00 AMD
    4318***0640
    ARARAT ATM, AM
    14.01.2025 12:00
    MNACORD 80,000.00
    """

    /// Отклонённая операция
    static let declined = """
    NOT ENOUGH FUNDS
    5,000.00 AMD
    4318***0640
    """

    /// Свободный формат без маски карты
    static let freeForm = "IDBank: Elq hashvic 5,000 AMD"
}
