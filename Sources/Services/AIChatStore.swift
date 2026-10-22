import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit

/// Распознанная операция в черновике: пользователь может снять отметку или поменять категорию до записи
struct DraftItem: Identifiable {
    let id = UUID()
    let parsed: ParsedSMSTransaction
    var isIncluded: Bool
    /// Такая операция уже есть в истории
    let isDuplicate: Bool
    /// Категория, выбранная вручную в черновике: при записи она запоминается для этого магазина
    var categoryOverride: Category? = nil

    /// Магазин или получатель, по которому запоминается категория (как в AutomationService)
    var merchant: String { parsed.brandName ?? parsed.title }

    /// Сумма в базовой валюте приложения
    @MainActor
    var amountInBase: Double {
        CurrencyService.shared.convert(amount: parsed.amount, from: parsed.currency, to: CurrencyManager.shared.baseCurrency)
    }

    /// Категория, с которой операция будет записана
    @MainActor
    var category: Category {
        categoryOverride
            ?? AutomationService.shared.learnedCategory(forMerchant: merchant, type: parsed.type)
            ?? FinanceService.shared.category(named: parsed.categoryName, type: parsed.type)
    }

    /// Категория подобрана наугад, и пользователь её ещё не выбирал
    @MainActor
    var needsReview: Bool {
        categoryOverride == nil
            && parsed.isCategoryGuessed
            && AutomationService.shared.learnedCategory(forMerchant: merchant, type: parsed.type) == nil
    }
}

/// Черновик операций, найденных на скриншотах или в тексте
struct OperationDraft {
    var items: [DraftItem]
    var isSaved = false

    var includedCount: Int { items.filter(\.isIncluded).count }
}

/// Сообщение в ИИ-чате
struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
    var thumbnails: [UIImage] = []
    var draft: OperationDraft? = nil
}

/// ИИ-чат: принимает скриншоты и тексты СМС, раскладывает операции по картам и категориям,
/// отвечает на вопросы о деньгах. Банковские СМС распознаются на телефоне; если пользователь сохранил ключ выбранного
/// облачного ИИ (Claude, ChatGPT или Gemini), остальное (вопросы, чеки, выписки, фразы о тратах) разбирает он.
/// Переписка живёт до закрытия приложения.
@Observable
@MainActor
final class AIChatStore {
    static let shared = AIChatStore()

    private(set) var messages: [ChatMessage] = []
    /// Чем сейчас занят помощник: распознаёт скриншоты или ждёт ответа облачного ИИ
    private(set) var workingText: String? = nil
    /// Облачный ИИ, выбранный в настройках
    private(set) var provider = AIProvider.selected
    /// Сохранён ли в настройках ключ выбранного облачного ИИ
    private(set) var isCloudEnabled = AIKeyStore.key(for: AIProvider.selected) != nil

    var isWorking: Bool { workingText != nil }

    private init() {
        messages = [Self.greeting()]
    }

    private static func greeting() -> ChatMessage {
        ChatMessage(
            role: .assistant,
            text: "Привет! Пришлите скриншоты банковских СМС или вставьте их текст — я найду операции, привяжу к картам и разложу по категориям. Ещё можно спросить, например: «сколько я потратил на продукты за неделю?»"
        )
    }

    /// Чат только с приветствием: показываем подсказки
    var isFresh: Bool { messages.count == 1 }

    func reset() {
        messages = [Self.greeting()]
        workingText = nil
    }

    /// Перечитывает выбранный сервис и его ключ после возврата из настроек
    func refreshCloudState() {
        provider = AIProvider.selected
        isCloudEnabled = AIKeyStore.key(for: provider) != nil
    }

    // MARK: - Текст

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWorking else { return }
        let history = cloudHistory()
        messages.append(ChatMessage(role: .user, text: trimmed))

        // Вставленный текст СМС разбирается на телефоне и сразу становится черновиком
        let found = Self.bankOperations(in: trimmed)
        if !found.isEmpty {
            presentDraft(found, intro: Self.foundText(count: found.count, source: "в тексте"))
            return
        }

        refreshCloudState()
        let activeProvider = provider
        guard let apiKey = AIKeyStore.key(for: activeProvider) else {
            reply(LocalFinanceAssistant.answer(trimmed, financeService: FinanceService.shared))
            return
        }
        workingText = "Думаю…"
        Task {
            await askCloud(trimmed, images: [], recognizedText: nil, history: history, provider: activeProvider, apiKey: apiKey)
        }
    }

    // MARK: - Скриншоты

    func send(screenshots items: [PhotosPickerItem]) async {
        guard !items.isEmpty, !isWorking else { return }
        workingText = "Распознаю текст…"
        defer { workingText = nil }

        var images: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                images.append(data)
            }
        }
        guard !images.isEmpty else {
            reply("Не получилось открыть изображения. Попробуйте выбрать их ещё раз.")
            return
        }

        let history = cloudHistory()
        let label = images.count == 1 ? "Скриншот" : "Скриншоты: \(images.count)"
        messages.append(ChatMessage(role: .user, text: label, thumbnails: images.compactMap { Self.thumbnail(from: $0) }))

        var texts: [String] = []
        for data in images {
            if let text = try? await ScreenshotTextRecognizer.recognizeText(in: data), !text.isEmpty {
                texts.append(text)
            }
        }
        let recognized = texts.joined(separator: "\n\n")

        // Сначала разбор на телефоне: банковские СМС не уходят в облако
        let found = Self.bankOperations(in: recognized)
        if !found.isEmpty {
            presentDraft(found, intro: Self.foundText(count: found.count, source: images.count == 1 ? "на скриншоте" : "на скриншотах"))
            return
        }

        // Чеки, выписки и приложения банков разбирает облачный ИИ, если есть ключ
        refreshCloudState()
        let activeProvider = provider
        if let apiKey = AIKeyStore.key(for: activeProvider) {
            workingText = "Разбираю скриншоты…"
            await askCloud(
                "Разбери скриншоты: найди операции, которые нужно записать в учёт. Если операций нет, коротко скажи, что на скриншотах.",
                images: images,
                recognizedText: recognized,
                history: history,
                provider: activeProvider,
                apiKey: apiKey
            )
            return
        }

        if texts.isEmpty {
            reply("Не нашёл текста на изображении. Нужен скриншот, где СМС банка видна целиком.")
        } else {
            reply("Текст распознал, но банковских СМС в нём нет. Подойдут СМС с суммой и маской карты, например «GNUM 3,500.00 AMD 4318***0640». Чтобы разбирать чеки и выписки, добавьте ключ Claude, ChatGPT или Gemini: Настройки → ИИ-помощник.")
        }
    }

    /// Уменьшенная копия для облачка сообщения с сохранением пропорций
    private static func thumbnail(from data: Data) -> UIImage? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(240 / image.size.width, 480 / image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return image.preparingThumbnail(of: size) ?? image
    }

    // MARK: - Облачный ИИ

    private func askCloud(_ question: String, images: [Data], recognizedText: String?, history: [CloudTurn], provider: AIProvider, apiKey: String) async {
        defer { workingText = nil }
        do {
            let answer = try await CloudFinanceAssistant.ask(
                question,
                images: images,
                recognizedText: recognizedText,
                history: history,
                provider: provider,
                apiKey: apiKey
            )
            if answer.operations.isEmpty {
                reply(answer.text)
            } else {
                presentDraft(answer.operations, intro: answer.text)
            }
        } catch is CancellationError {
            return
        } catch {
            HapticManager.shared.trigger(.error)
            reply((error as? LocalizedError)?.errorDescription ?? "Не получилось получить ответ \(provider.displayName). Повторите запрос.")
        }
    }

    /// Переписка для облачного ИИ: только текст, без приветствия и картинок
    private func cloudHistory() -> [CloudTurn] {
        messages.dropFirst().map { message in
            var text = message.text
            if let draft = message.draft {
                let status = draft.isSaved ? "записаны" : "ждут подтверждения"
                let list = draft.items
                    .map { "\($0.parsed.title) \($0.parsed.amount) \($0.parsed.currency.rawValue)" }
                    .joined(separator: "; ")
                text += "\n[Черновик операций, \(status): \(list)]"
            }
            return CloudTurn(isUser: message.role == .user, text: text)
        }
    }

    // MARK: - Черновик

    /// Операции из текста без повторов. Настоящая СМС почти всегда содержит маску карты, остаток или дату,
    /// а случайные числа со скриншота (время, проценты заряда) — нет: такие находки отбрасываются.
    private static func bankOperations(in text: String) -> [ParsedSMSTransaction] {
        var seen = Set<String>()
        return SMSParser.parseBatch(text: text).filter { parsed in
            guard parsed.cardLast4 != nil || parsed.balanceAfter != nil || parsed.date != nil else { return false }
            return seen.insert(parsed.dedupKey).inserted
        }
    }

    private static func foundText(count: Int, source: String) -> String {
        let text = count == 1 ? "Нашёл операцию \(source)." : "Нашёл операций \(source): \(count)."
        return text + " Проверьте категории и нажмите «Записать»."
    }

    private func presentDraft(_ found: [ParsedSMSTransaction], intro: String) {
        let financeService = FinanceService.shared
        let items = found.map { parsed in
            let duplicate = financeService.hasTransaction(externalKey: parsed.dedupKey)
            return DraftItem(parsed: parsed, isIncluded: !duplicate, isDuplicate: duplicate)
        }
        let duplicates = items.filter(\.isDuplicate).count

        var text = intro
        if duplicates > 0 {
            text += " Уже записаны: \(duplicates), их отметку я снял."
        }
        HapticManager.shared.trigger(.success)
        messages.append(ChatMessage(role: .assistant, text: text, draft: OperationDraft(items: items)))
    }

    func toggle(itemID: UUID, in messageID: UUID) {
        updateDraft(messageID) { draft in
            guard let index = draft.items.firstIndex(where: { $0.id == itemID }) else { return }
            draft.items[index].isIncluded.toggle()
        }
    }

    func setCategory(_ category: Category, itemID: UUID, in messageID: UUID) {
        updateDraft(messageID) { draft in
            guard let index = draft.items.firstIndex(where: { $0.id == itemID }) else { return }
            draft.items[index].categoryOverride = category
        }
    }

    /// Записывает отмеченные операции: карты, балансы, дубли и переводы между своими картами обрабатывает AutomationService
    func saveDraft(in messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              let draft = messages[index].draft, !draft.isSaved else { return }
        let chosen = draft.items.filter(\.isIncluded)
        guard !chosen.isEmpty else { return }

        // Ручной выбор категории запоминается: в следующий раз этот магазин разложится сам
        for item in chosen {
            if let category = item.categoryOverride {
                AutomationService.shared.learnCategory(merchant: item.merchant, category: category)
            }
        }

        let summary = AutomationService.shared.ingestAll(chosen.map(\.parsed))
        messages[index].draft?.isSaved = true
        HapticManager.shared.trigger(summary.failed > 0 ? .error : .success)
        reply("Готово: \(summary.text). Балансы карт обновлены.")
    }

    private func updateDraft(_ messageID: UUID, _ change: (inout OperationDraft) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              var draft = messages[index].draft, !draft.isSaved else { return }
        change(&draft)
        messages[index].draft = draft
    }

    private func reply(_ text: String) {
        messages.append(ChatMessage(role: .assistant, text: text))
    }
}
