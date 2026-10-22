import SwiftUI

/// Экран новой операции: сначала сумма на цифровой клавиатуре, затем категория, название и дата.
/// Умеет распознавать СМС из буфера и пакетно импортировать раннюю историю СМС.
struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService

    @State private var amountString: String = ""
    @State private var title: String = ""
    @State private var transactionType: TransactionType
    @State private var selectedCategory: Category
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var isShowingBatchImport = false

    // Результат распознавания
    @State private var recognitionMessage: String? = nil
    @State private var recognitionSucceeded = false

    private static let keypadKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ",", "0", "⌫"]

    init(financeService: FinanceService, initialType: TransactionType = .expense) {
        self.financeService = financeService
        _transactionType = State(initialValue: initialType)
        let firstCategory = financeService.categories.first { $0.type == initialType } ?? financeService.categories[0]
        _selectedCategory = State(initialValue: firstCategory)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    typePicker
                    amountDisplay
                    categoryChips
                    detailRows
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)

            bottomPanel
        }
        .monoScreen()
        .sheet(isPresented: $isShowingBatchImport) {
            BatchSMSImportSheet(financeService: financeService)
        }
    }

    // MARK: - Верхняя строка
    private var topBar: some View {
        HStack {
            MonoCircleButton(systemName: "xmark", label: "Закрыть") {
                dismiss()
            }
            Spacer()
            Text("Новая операция")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var typePicker: some View {
        MonoSegmentedControl(
            options: [TransactionType.expense, TransactionType.income],
            title: { $0 == .expense ? "Расход" : "Доход" },
            selection: $transactionType
        )
        .padding(.top, 12)
        .onChange(of: transactionType) { _, newValue in
            if selectedCategory.type != newValue,
               let first = financeService.categories.first(where: { $0.type == newValue }) {
                selectedCategory = first
            }
        }
    }

    // MARK: - Сумма
    private var amountDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: "Сумма")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CurrencyManager.shared.baseCurrency.symbol)
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Theme.textTertiary)
                Text(displayAmount)
                    .font(.system(size: 56, weight: .light))
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundColor(amountString.isEmpty ? Theme.textTertiary : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(.top, 24)
    }

    /// Введённая сумма с пробелами между разрядами
    private var displayAmount: String {
        if amountString.isEmpty {
            return "0"
        }
        let parts = amountString.split(separator: ",", omittingEmptySubsequences: false)
        let integerPart = String(parts[0])
        let grouped = groupDigits(integerPart.isEmpty ? "0" : integerPart)
        if parts.count > 1 {
            return grouped + "," + String(parts[1])
        }
        return grouped
    }

    private func groupDigits(_ digits: String) -> String {
        var result = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0 && offset % 3 == 0 {
                result.append(" ")
            }
            result.append(character)
        }
        return String(result.reversed())
    }

    // MARK: - Категории
    private var categoryChips: some View {
        let categories = financeService.categories.filter { $0.type == transactionType }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    categoryChip(category)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.horizontal, -24)
        .padding(.top, 20)
    }

    private func categoryChip(_ category: Category) -> some View {
        let isSelected = selectedCategory.id == category.id
        return Button {
            HapticManager.shared.selection()
            selectedCategory = category
        } label: {
            Text(category.name)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Theme.onAccent : .white)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(isSelected ? Theme.accent : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: isSelected ? 0 : 1))
        }
    }

    // MARK: - Строки с деталями
    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            row {
                Button {
                    recognizeSMSFromClipboard()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Распознать СМС из буфера")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .font(.system(size: 15))
                    .foregroundColor(Theme.accent)
                }
            }

            row {
                Button {
                    HapticManager.shared.impact(.light)
                    isShowingBatchImport = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "text.badge.plus")
                        Text("Импорт ранней истории СМС")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                }
            }

            if let recognitionMessage {
                Text(recognitionMessage)
                    .font(.system(size: 13))
                    .foregroundColor(recognitionSucceeded ? Theme.accent : Theme.textSecondary)
                    .padding(.vertical, 8)
            }

            row {
                HStack {
                    Text("Название")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textSecondary)
                    TextField("Напр., Покупка кофе", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }
            }

            row {
                DatePicker("Дата", selection: $date, displayedComponents: .date)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textSecondary)
                    .tint(Theme.accent)
            }

            row {
                HStack {
                    Text("Заметка")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textSecondary)
                    TextField("Необязательно", text: $notes)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
                .frame(minHeight: 48)
            MonoDivider()
        }
    }

    // MARK: - Клавиатура и кнопка сохранения
    private var bottomPanel: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 0) {
                ForEach(Self.keypadKeys, id: \.self) { key in
                    keypadButton(key)
                }
            }

            PrimaryButton(title: "Сохранить", isEnabled: parsedAmount > 0) {
                saveTransaction()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func keypadButton(_ key: String) -> some View {
        Button {
            press(key)
        } label: {
            Group {
                if key == "⌫" {
                    Image(systemName: "delete.left")
                        .font(.system(size: 22))
                } else {
                    Text(key)
                        .font(.system(size: 26))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .accessibilityLabel(key == "⌫" ? "Стереть" : key)
    }

    /// Ввод с клавиатуры: до 9 цифр в целой части и до 2 после запятой
    private func press(_ key: String) {
        HapticManager.shared.selection()
        switch key {
        case "⌫":
            if !amountString.isEmpty {
                amountString.removeLast()
            }
        case ",":
            if !amountString.contains(",") {
                amountString = amountString.isEmpty ? "0," : amountString + ","
            }
        default:
            let parts = amountString.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count > 1 {
                if parts[1].count >= 2 { return }
            } else if let integerPart = parts.first, integerPart.count >= 9 {
                return
            }
            amountString = amountString == "0" ? key : amountString + key
        }
    }

    private var parsedAmount: Double {
        Double(amountString.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    // MARK: - Сохранение
    private func saveTransaction() {
        let amount = parsedAmount
        guard amount > 0 else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmedTitle.isEmpty ? selectedCategory.name : trimmedTitle
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let newTransaction = Transaction(
            title: finalTitle,
            amount: amount,
            type: transactionType,
            category: selectedCategory,
            date: date,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            brandName: finalTitle,
            brandIcon: selectedCategory.icon,
            brandColorHex: selectedCategory.colorHex
        )

        financeService.addTransaction(newTransaction)
        if !trimmedTitle.isEmpty {
            // В следующий раз этот магазин получит выбранную категорию сам
            AutomationService.shared.learnCategory(merchant: trimmedTitle, category: selectedCategory)
        }
        HapticManager.shared.trigger(.success)
        dismiss()
    }

    // MARK: - Распознавание СМС
    private func recognizeSMSFromClipboard() {
        HapticManager.shared.impact(.light)
        guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else {
            recognitionSucceeded = false
            recognitionMessage = "Буфер обмена пуст."
            return
        }

        if let parsed = SMSParser.parse(text: clipboardText) {
            title = parsed.title
            amountString = inputString(for: parsed.amount)
            transactionType = parsed.type
            selectedCategory = financeService.category(named: parsed.categoryName, type: parsed.type)
            if let parsedDate = parsed.date {
                date = parsedDate
            }

            recognitionSucceeded = true
            recognitionMessage = "Успешно распознано: \(parsed.title) (\(CurrencyManager.shared.format(parsed.amount)))"
            HapticManager.shared.trigger(.success)
        } else {
            recognitionSucceeded = false
            recognitionMessage = "Не удалось распознать формат СМС."
            HapticManager.shared.trigger(.error)
        }
    }

    /// Сумма в формате поля ввода: целые без дробной части, остальные с двумя знаками и запятой
    private func inputString(for amount: Double) -> String {
        if amount == amount.rounded() {
            return String(Int(amount))
        }
        return String(format: "%.2f", amount).replacingOccurrences(of: ".", with: ",")
    }
}

/// Модальный экран пакетного сканирования и распознавания всей ранней истории СМС сообщений
struct BatchSMSImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService

    @State private var batchText: String = ""
    @State private var recognizedTransactions: [ParsedSMSTransaction] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Вставьте текст вашей истории СМС сообщений за прошлые периоды. Парсер распознает все операции списком.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                TextEditor(text: $batchText)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(.white)
                    .frame(height: 140)
                    .padding(8)
                    .monoSurface(cornerRadius: 16)
                    .padding(.horizontal, 24)

                actionRow

                resultsList
            }
            .padding(.top, 16)
            .monoScreen()
            .navigationTitle("Импорт ранней истории СМС")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Импортировать все (\(recognizedTransactions.count))") {
                        importAllRecognized()
                    }
                    .disabled(recognizedTransactions.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var actionRow: some View {
        HStack {
            Button {
                if let clipboard = UIPasteboard.general.string {
                    batchText = clipboard
                    HapticManager.shared.impact(.light)
                }
            } label: {
                Label("Вставить из буфера", systemImage: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .frame(minHeight: 44)
            }

            Spacer()

            Button {
                HapticManager.shared.trigger(.success)
                withAnimation {
                    recognizedTransactions = SMSParser.parseBatch(text: batchText)
                }
            } label: {
                Text("Распознать все СМС (\(recognizedTransactions.count))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.onAccent)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var resultsList: some View {
        if recognizedTransactions.isEmpty {
            Spacer()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    MonoLabel(text: "Найдено операций: \(recognizedTransactions.count)")

                    ForEach(0..<recognizedTransactions.count, id: \.self) { index in
                        resultRow(recognizedTransactions[index])
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func resultRow(_ parsed: ParsedSMSTransaction) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(parsed.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(parsed.categoryName)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textTertiary)
                }

                Spacer(minLength: 8)

                Text("\(parsed.type == .income ? "+" : "−")\(CurrencyManager.shared.format(parsed.amount))")
                    .font(.system(size: 16))
                    .monospacedDigit()
                    .foregroundColor(parsed.type == .income ? Theme.accent : .white)
            }
            .frame(minHeight: 56)
            MonoDivider()
        }
    }

    private func importAllRecognized() {
        // Карта, баланс, дубли и категория обрабатываются автоматически, по порядку дат
        _ = AutomationService.shared.ingestAll(recognizedTransactions)

        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
