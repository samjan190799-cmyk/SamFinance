import SwiftUI

/// Экран создания новой финансовой транзакции с валидацией, тактильной отдачей
/// и поддержкой быстрого одиночного и пакетного распознавания ранних СМС из буфера/истории.
struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    
    @State private var amountString: String = ""
    @State private var title: String = ""
    @State private var transactionType: TransactionType = .expense
    @State private var selectedCategory: Category
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var isShowingBatchImport = false
    
    // Результат распознавания
    @State private var recognitionMessage: String? = nil
    
    init(financeService: FinanceService) {
        self.financeService = financeService
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
                    
                    Button {
                        HapticManager.shared.impact(.light)
                        isShowingBatchImport = true
                    } label: {
                        HStack {
                            Image(systemName: "text.badge.plus")
                                .foregroundColor(.blue)
                            Text("Импорт ранней истории СМС")
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
                    Text("Быстрый ввод и парсер СМС")
                }
                
                Section {
                    Picker("Тип транзакции", selection: $transactionType) {
                        Text("Расход").tag(TransactionType.expense)
                        Text("Доход").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: transactionType) { _, newValue in
                        HapticManager.shared.selection()
                        if let firstOfNewType = financeService.categories.first(where: { $0.type == newValue }) {
                            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.75)) {
                                selectedCategory = firstOfNewType
                            }
                        }
                    }
                    
                    HStack {
                        Text("Сумма ($)")
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
                                    HapticManager.shared.selection()
                                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.75)) {
                                        selectedCategory = category
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("Выбор категории")
                }
                
                Section {
                    TextField("Заметка (опционально)", text: $notes)
                } header: {
                    Text("Дополнительно")
                }
            }
            .navigationTitle("Новая транзакция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saveTransaction()
                    }
                    .disabled(isSaveDisabled)
                    .fontWeight(.bold)
                }
            }
            .sheet(isPresented: $isShowingBatchImport) {
                BatchSMSImportSheet(financeService: financeService)
            }
        }
    }
    
    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        Double(amountString.replacingOccurrences(of: ",", with: ".")) ?? 0 <= 0
    }
    
    private func saveTransaction() {
        guard let amount = Double(amountString.replacingOccurrences(of: ",", with: ".")) else { return }
        
        let newTransaction = Transaction(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            type: transactionType,
            category: selectedCategory,
            date: date,
            notes: notes.isEmpty ? nil : notes,
            brandName: title,
            brandIcon: selectedCategory.icon,
            brandColorHex: selectedCategory.colorHex
        )
        
        financeService.addTransaction(newTransaction)
        HapticManager.shared.trigger(.success)
        dismiss()
    }
    
    private func recognizeSMSFromClipboard() {
        HapticManager.shared.impact(.light)
        guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else {
            withAnimation {
                recognitionMessage = "Буфер обмена пуст."
            }
            return
        }
        
        if let parsed = SMSParser.parse(text: clipboardText) {
            title = parsed.title
            amountString = String(format: "%.2f", parsed.amount)
            transactionType = parsed.type
            if let matchedCat = financeService.categories.first(where: { $0.name == parsed.categoryName }) {
                selectedCategory = matchedCat
            }
            
            withAnimation {
                recognitionMessage = "Успешно распознано: \(parsed.title) (\(parsed.amount) $)"
            }
            HapticManager.shared.trigger(.success)
        } else {
            withAnimation {
                recognitionMessage = "Не удалось распознать формат СМС."
            }
            HapticManager.shared.trigger(.error)
        }
    }
}

/// Пузырек выбора категории
struct CategoryBubble: View {
    let category: Category
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category.icon)
                .font(.system(size: 13))
            Text(category.name)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color(hex: category.colorHex) : Color.white.opacity(0.1))
        .foregroundColor(isSelected ? .white : .gray)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isSelected ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
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
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                TextEditor(text: $batchText)
                    .frame(height: 140)
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    .padding(.horizontal, 16)
                
                HStack {
                    Button {
                        if let clipboard = UIPasteboard.general.string {
                            batchText = clipboard
                            HapticManager.shared.impact(.light)
                        }
                    } label: {
                        Label("Вставить из буфера", systemImage: "doc.on.clipboard")
                            .font(.caption.bold())
                    }
                    
                    Spacer()
                    
                    Button {
                        HapticManager.shared.trigger(.success)
                        withAnimation {
                            recognizedTransactions = SMSParser.parseBatch(text: batchText)
                        }
                    } label: {
                        Text("Распознать все СМС (\(recognizedTransactions.count))")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                
                // Список распознанных ранних СМС
                if !recognizedTransactions.isEmpty {
                    List {
                        Section {
                            ForEach(0..<recognizedTransactions.count, id: \.self) { index in
                                let t = recognizedTransactions[index]
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.title)
                                            .fontWeight(.bold)
                                        Text(t.categoryName)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    Text("$\(Int(t.amount))")
                                        .fontWeight(.bold)
                                        .foregroundColor(t.type == .expense ? .red : .green)
                                }
                            }
                        } header: {
                            Text("Найдено операций: \(recognizedTransactions.count)")
                        }
                    }
                } else {
                    Spacer()
                }
            }
            .padding(.top, 16)
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
                    .fontWeight(.bold)
                }
            }
        }
    }
    
    private func importAllRecognized() {
        for parsed in recognizedTransactions {
            let category = financeService.categories.first(where: { $0.name == parsed.categoryName }) ?? financeService.categories[0]
            let transaction = Transaction(
                title: parsed.title,
                amount: parsed.amount,
                type: parsed.type,
                category: category,
                date: Date(),
                notes: "Импортировано из ранней истории СМС",
                brandName: parsed.brandName,
                brandIcon: category.icon,
                brandColorHex: category.colorHex
            )
            financeService.addTransaction(transaction)
        }
        
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
