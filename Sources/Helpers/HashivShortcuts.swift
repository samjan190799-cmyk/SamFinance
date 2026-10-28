import AppIntents

/// Выставляет действия Hashiv напоказ: без этого блока приложение не появляется в поиске «Быстрых команд»
/// и Siri не знает его действий. Здесь два действия: подсказка после оплаты Apple Pay и распознавание банковских СМС.
/// Обычно они подключаются к автоматизациям «Транзакция» и «Сообщение», а голосом вызываются редко.
struct HashivShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordPurchaseIntent(),
            phrases: [
                "Record an Apple Pay purchase in \(.applicationName)",
                "Record a purchase in \(.applicationName)"
            ],
            shortTitle: "Записать покупку Apple Pay",
            systemImageName: "creditcard.fill"
        )
        AppShortcut(
            intent: ProcessSMSIntent(),
            phrases: [
                "Process a bank SMS in \(.applicationName)",
                "Record a bank message in \(.applicationName)"
            ],
            shortTitle: "Распознать СМС транзакцию",
            systemImageName: "message.fill"
        )
    }
}
