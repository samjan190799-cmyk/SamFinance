import AppIntents
import Foundation

/// Ошибки действия распознавания СМС
enum ProcessSMSError: Error, CustomLocalizedStringResourceConvertible {
    case storageUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storageUnavailable:
            return "Данные SamFinance сейчас недоступны (возможно, телефон заблокирован). Операция не сохранена."
        }
    }
}

/// Системное действие для автоматического парсинга СМС через Быстрые команды (Siri Shortcuts).
/// Привязывается к автоматизации «Сообщение»: операция записывается, карта и её баланс обновляются сами.
@available(iOS 16.0, *)
public struct ProcessSMSIntent: AppIntent {
    public static var title: LocalizedStringResource { "Распознать СМС транзакцию" }
    public static var description: IntentDescription? { "Парсит текст банковской СМС, записывает операцию в SamFinance и обновляет баланс карты." }

    // Входной параметр — текст СМС, передаваемый из приложения "Быстрые команды"
    @Parameter(title: "Текст СМС")
    public var smsText: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Распознать транзакцию из \(\.$smsText)")
    }

    public init() {
        self.smsText = ""
    }

    public init(smsText: String) {
        self.smsText = smsText
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // Парсим СМС через наш SMSParser
        guard let parsed = SMSParser.parse(text: smsText) else {
            return .result(dialog: "Это не похоже на банковскую операцию, пропускаю")
        }

        // Дальше всё делает автоматизация: карта, баланс, дубли, категория
        let result = AutomationService.shared.ingest(parsed)

        // Если файл данных сейчас недоступен (например, телефон заблокирован),
        // сообщаем об ошибке в Быстрых командах, а не теряем СМС молча.
        if case .storageUnavailable = result {
            throw ProcessSMSError.storageUnavailable
        }

        return .result(dialog: "\(result.message)")
    }
}
