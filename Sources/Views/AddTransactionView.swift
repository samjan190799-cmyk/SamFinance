import SwiftUI

/// Экран создания новой финансовой транзакции с валидацией, тактильной отдачей и микро-анимациями.
struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    
    @State private var amountString: String = ""
    @State private var title: String = ""
    @State private var transactionType: TransactionType = .expense
    @State private var selectedCategory: Category
    @State private var date: Date = Date()
    @State private var notes: String = ""
    
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
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        )
        
        financeService.addTransaction(transaction)
        HapticManager.shared.trigger(.success)
        dismiss()
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

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 1)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
