import SwiftUI

/// Экран создания новой финансовой транзакции с валидацией, тактильной отдачей
/// и поддержкой быстрого импорта/распознавания СМС из буфера обмена.
struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    
    @State private var amountString: String = ""
    @State private var title: String = ""
    @State private var transactionType: TransactionType = .expense
    @State private var selectedCategory: Category
    @State private var date: Date = Date()
    @State private var notes: String = ""
    
    // Результат распознавания
    @State private var recognitionMessage: String? = nil
    
    init(financeService: FinanceService) {
        self.financeService = financeService
        // По умолчанию выбираем первую категорию расходов
        let defaultCategory = financeService.categories.first { $0.type == .expense } ?? financeService.categories[0]
        _selectedCategory = State(initialValue: defaultCategory)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        recognizeSMSFromClipboard()
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.clipboard.fill")
                                .foregroundColor(.orange)
                            Text("Распознать СМС из буфера")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .foregroundColor(.white)
                    
                    if let msg = recognitionMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(msg.contains("Успешно") ? .green : .red)
                    }
                } header: {
                    Text("Быстрый ввод из банка")
                }
                
                Section {
                    Picker("Тип транзакции", selection: $transactionType) {
                        Text("Расход").tag(TransactionType.expense)
                        Text("Доход").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: transactionType) { _, newValue in
                        HapticManager.shared.selection()
                        // Автоматическая смена выбранной категории на соответствующую новому типу
                        if let firstOfNewType = financeService.categories.first(where: { $0.type == newValue }) {
                            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.75)) {
                                selectedCategory = firstOfNewType
                            }
                        }
                    }
                    
                    HStack {
                        Text("Сумма")
                            .font(.headline)
                        Spacer()
                        TextField("0", text: $amountString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title2.bold())
                            .foregroundColor(transactionType == .expense ? .red : .green)
                    }
                } header: {
                    Text("Основные параметры")
                }
                
                Section {
                    TextField("Описание (напр., Покупка кофе)", text: $title)
                        .textInputAutocapitalization(.sentences)
                    
                    DatePicker("Дата операции", selection: $date, displayedComponents: .date)
                } header: {
                    Text("Детали платежа")
                }
                
                Section {
                    let filteredCategories = financeService.categories.filter { $0.type == transactionType }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(filteredCategories) { category in
                                CategoryBubble(
                                    category: category,
                                    isSelected: selectedCategory.id == category.id
                                )
                                .onTapGesture {
                                    HapticManager.shared.impact(.light)
                                    withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedCategory = category
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Выберите категорию")
                }
                
                Section {
                    TextField("Заметки", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                } header: {
                    Text("Дополнительно")
                }
            }
            .navigationTitle("Новая операция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        HapticManager.shared.impact(.light)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        saveTransaction()
                    }
                    .font(.headline)
                    .disabled(isSaveDisabled)
                }
            }
        }
    }
    
    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        Double(amountString.replacingOccurrences(of: ",", with: ".")) ?? 0 <= 0
    }
    
    private func saveTransaction() {
        guard let amount = Double(amountString.replacingOccurrences(of: ",", with: ".")) else { return }
        
        let transaction = Transaction(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            type: transactionType,
            category: selectedCategory,
            date: date,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            brandName: title.trimmingCharacters(in: .whitespacesAndNewlines),
            brandIcon: selectedCategory.icon,
            brandColorHex: selectedCategory.colorHex
        )
        
        financeService.addTransaction(transaction)
        HapticManager.shared.trigger(.success)
        dismiss()
    }
    
    private func recognizeSMSFromClipboard() {
        guard let clipboardString = UIPasteboard.general.string,
              !clipboardString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            HapticManager.shared.trigger(.error)
            recognitionMessage = "Буфер обмена пуст"
            return
        }
        
        if let parsed = SMSParser.parse(text: clipboardString) {
            HapticManager.shared.trigger(.success)
            // Форматируем сумму без лишних копеек, если они равны нулю
            if parsed.amount.truncatingRemainder(dividingBy: 1) == 0 {
                amountString = String(format: "%.0f", parsed.amount)
            } else {
                amountString = String(format: "%.2f", parsed.amount)
            }
            transactionType = parsed.type
            title = parsed.title
            
            if let matchedCat = financeService.categories.first(where: { $0.name == parsed.categoryName }) {
                selectedCategory = matchedCat
            }
            
            recognitionMessage = "Успешно распознано: \(parsed.title) (\(Int(parsed.amount)) $)"
            
            // Очищаем буфер для безопасности
            UIPasteboard.general.string = ""
        } else {
            HapticManager.shared.trigger(.error)
            recognitionMessage = "Не удалось распознать формат СМС"
        }
    }
}

/// Элемент выбора категории в виде пилюли
struct CategoryBubble: View {
    let category: Category
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category.icon)
                .font(.body.bold())
            Text(category.name)
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            if isSelected {
                Color(hex: category.colorHex)
            } else {
                Color(.systemGray6)
            }
        }
        .foregroundColor(isSelected ? .white : .primary)
        .clipShape(Capsule())
        .overlay {
            if isSelected {
                Capsule()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            }
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
    }
}
