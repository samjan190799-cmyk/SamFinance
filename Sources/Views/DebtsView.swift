import SwiftUI

/// Экран управления долгами с вкладками «Кредиты» и «Люди» в соответствии со стилем приложения.
/// Без лишнего пустого пространства сверху и с белой шторкой, уходящей до низа экрана.
struct DebtsView: View {
    let financeService: FinanceService
    @State private var selectedSegment = 0 // 0: Кредиты, 1: Люди
    @State private var isShowingAddSheet = false
    
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.height < 750
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                Color(hex: "#090A0E")
                    .ignoresSafeArea()
                
                Circle()
                    .fill(Color(hex: "#00E676").opacity(0.10))
                    .frame(width: 260, height: 260)
                    .blur(radius: 85)
                    .offset(x: -100, y: -120)
                
                Circle()
                    .fill(Color(hex: "#7C4DFF").opacity(0.12))
                    .frame(width: 260, height: 260)
                    .blur(radius: 85)
                    .offset(x: 120, y: 100)
            }
            
            VStack(spacing: 0) {
                // Шапка
                headerView
                    .padding(.horizontal, 24)
                    .padding(.top, isSmallScreen ? 34 : 54)
                
                // Переключатель сегментов «Кредиты / Люди»
                customSegmentControl
                    .padding(.horizontal, 24)
                    .padding(.top, isSmallScreen ? 12 : 20)
                    .padding(.bottom, isSmallScreen ? 16 : 24)
                
                // Белая шторка со списком
                debtsBottomSheet
            }
            .ignoresSafeArea(edges: .bottom) // Позволяет белой шторке уходить до низа экрана
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingAddSheet) {
            AddDebtView(financeService: financeService)
        }
    }
    
    // MARK: - Шапка
    private var headerView: some View {
        HStack {
            Text("debts_title".localized)
                .font(.system(size: isSmallScreen ? 28 : 32, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            Button {
                HapticManager.shared.impact(.light)
                isShowingAddSheet = true
            } label: {
                Text("add_debt".localized)
                    .font(.system(size: isSmallScreen ? 11 : 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, isSmallScreen ? 12 : 16)
                    .padding(.vertical, isSmallScreen ? 6 : 8)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Переключатель "Кредиты / Люди"
    private var customSegmentControl: some View {
        HStack(spacing: 0) {
            Button {
                HapticManager.shared.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    selectedSegment = 0
                }
            } label: {
                Text("credits_tab".localized)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(selectedSegment == 0 ? .black : .white.opacity(0.45))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(selectedSegment == 0 ? Color.white : Color.clear)
                    .clipShape(Capsule())
            }
            
            Button {
                HapticManager.shared.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    selectedSegment = 1
                }
            } label: {
                Text("people_tab".localized)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(selectedSegment == 1 ? .black : .white.opacity(0.45))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(selectedSegment == 1 ? Color.white : Color.clear)
                    .clipShape(Capsule())
            }
        }
        .padding(4)
        .background(Color(hex: "#17181A"))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
    
    // MARK: - Шторка списка
    private var debtsBottomSheet: some View {
        let filteredDebts = financeService.debts.filter { debt in
            if selectedSegment == 0 {
                return debt.type == .credit
            } else {
                return debt.type == .person
            }
        }
        
        return VStack(spacing: 0) {
            if filteredDebts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: selectedSegment == 0 ? "building.columns.fill" : "person.2.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.35))
                        .symbolRenderingMode(.hierarchical)
                    
                    Text("Пусто")
                        .font(.headline)
                        .foregroundColor(.black.opacity(0.6))
                    
                    Text(selectedSegment == 0 ? "У вас нет активных кредитов." : "У вас нет активных долгов людям.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(.rect(topLeadingRadius: isSmallScreen ? 24 : 32, topTrailingRadius: isSmallScreen ? 24 : 32))
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        ForEach(filteredDebts) { debt in
                            DebtRowView(debt: debt, financeService: financeService)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        HapticManager.shared.trigger(.warning)
                                        withAnimation(.spring()) {
                                            financeService.deleteDebt(id: debt.id)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, isSmallScreen ? 110 : 140)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(.rect(topLeadingRadius: isSmallScreen ? 24 : 32, topTrailingRadius: isSmallScreen ? 24 : 32))
            }
        }
    }
}

/// Строка долга на шторке
struct DebtRowView: View {
    let debt: Debt
    let financeService: FinanceService
    
    var body: some View {
        HStack(spacing: 16) {
            // Иконка в зависимости от типа долга с точкой статуса
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 44, height: 44)
                
                Image(systemName: debt.type == .credit ? "building.columns.fill" : "person.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.black.opacity(0.5))
                
                Circle()
                    .fill(debt.isLent ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(debt.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(debt.isPaid ? .gray : .black)
                    .strikethrough(debt.isPaid)
                
                Text("Срок: \(formatDate(debt.dueDate))")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text("\(formatAmount(debt.amount)) $")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(debt.isPaid ? .gray : (debt.isLent ? .green : .red))
                .strikethrough(debt.isPaid)
            
            Button {
                HapticManager.shared.trigger(.success)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    financeService.togglePayDebt(id: debt.id)
                }
            } label: {
                Image(systemName: debt.isPaid ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.title3)
                    .foregroundColor(debt.isPaid ? .green : .gray)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.string(from: date)
    }
    
    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// Модальный экран создания нового долга
struct AddDebtView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    
    @State private var name: String = ""
    @State private var amountString: String = ""
    @State private var isLent: Bool = false
    @State private var selectedType: DebtType = .credit
    @State private var dueDate: Date = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Категория долга", selection: $selectedType) {
                        Text("Кредит").tag(DebtType.credit)
                        Text("Человек").tag(DebtType.person)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedType) { _, newValue in
                        if newValue == .credit {
                            isLent = false // Кредит - всегда "Я должен"
                        }
                    }
                } header: {
                    Text("Категория")
                }
                
                Section {
                    TextField(selectedType == .credit ? "Название банка / кредитора" : "Имя человека", text: $name)
                        .textInputAutocapitalization(.words)
                    
                    HStack {
                        Text("Сумма ($)")
                        Spacer()
                        TextField("0", text: $amountString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Информация о долге")
                }
                
                if selectedType == .person {
                    Section {
                        Picker("Кто кому должен", selection: $isLent) {
                            Text("Мне должны").tag(true)
                            Text("Я должен").tag(false)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Направление")
                    }
                }
                
                Section {
                    DatePicker("Срок возврата", selection: $dueDate, displayedComponents: .date)
                } header: {
                    Text("Сроки")
                }
            }
            .navigationTitle("Новый долг")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saveDebt()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }
    
    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        Double(amountString.replacingOccurrences(of: ",", with: ".")) ?? 0 <= 0
    }
    
    private func saveDebt() {
        guard let amount = Double(amountString.replacingOccurrences(of: ",", with: ".")) else { return }
        let debt = Debt(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            dueDate: dueDate,
            isLent: selectedType == .credit ? false : isLent,
            isPaid: false,
            type: selectedType
        )
        financeService.addDebt(debt)
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
