import SwiftUI

/// Экран управления взаиморасчетами (долгами) с поддержкой сегмент-контроля,
/// создания новых долгов и отметки о выплате.
struct DebtsView: View {
    let financeService: FinanceService
    @State private var selectedSegment = 0 // 0: Мне должны (Lent), 1: Я должен (Borrowed)
    @State private var isShowingAddSheet = false
    
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.height < 750
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(hex: "#0E0F12") // Стильный темный фон
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Шапка
                    headerView
                        .padding(.horizontal, 24)
                        .padding(.top, isSmallScreen ? 4 : 8)
                    
                    // Переключатель сегментов
                    customSegmentControl
                        .padding(.horizontal, 24)
                        .padding(.top, isSmallScreen ? 12 : 20)
                        .padding(.bottom, isSmallScreen ? 16 : 24)
                    
                    // Белая шторка со списком
                    debtsBottomSheet
                }
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: $isShowingAddSheet) {
                AddDebtView(financeService: financeService)
            }
        }
    }
    
    // MARK: - Шапка
    private var headerView: some View {
        HStack {
            Text("Debts")
                .font(.system(size: isSmallScreen ? 28 : 32, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            Button {
                HapticManager.shared.impact(.light)
                isShowingAddSheet = true
            } label: {
                Text("Add debt")
                    .font(.system(size: isSmallScreen ? 11 : 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, isSmallScreen ? 12 : 16)
                    .padding(.vertical, isSmallScreen ? 6 : 8)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Переключатель "Lent / Borrowed"
    private var customSegmentControl: some View {
        HStack(spacing: 0) {
            Button {
                HapticManager.shared.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    selectedSegment = 0
                }
            } label: {
                Text("Lent")
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
                Text("Borrowed")
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
    
    // MARK: - Шторка списка долгов
    private var debtsBottomSheet: some View {
        let filteredDebts = financeService.debts.filter { $0.isLent == (selectedSegment == 0) }
        
        return VStack(spacing: 0) {
            if filteredDebts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.35))
                        .symbolRenderingMode(.hierarchical)
                    
                    Text("No active debts")
                        .font(.headline)
                        .foregroundColor(.black.opacity(0.6))
                    
                    Text(selectedSegment == 0 ? "No one owes you money right now." : "You don't owe money to anyone right now.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(.rect(topLeadingRadius: isSmallScreen ? 24 : 32, topTrailingRadius: isSmallScreen ? 24 : 32))
                .ignoresSafeArea(edges: .bottom)
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
                    .padding(.bottom, isSmallScreen ? 90 : 110)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(.rect(topLeadingRadius: isSmallScreen ? 24 : 32, topTrailingRadius: isSmallScreen ? 24 : 32))
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

/// Строка конкретного долга
struct DebtRowView: View {
    let debt: Debt
    let financeService: FinanceService
    
    var body: some View {
        HStack(spacing: 16) {
            // Иконка контакта с цветной точкой статуса
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "person.fill")
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
                
                Text("Due: \(formatDate(debt.dueDate))")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text("\(formatAmount(debt.amount)) $")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(debt.isPaid ? .gray : (debt.isLent ? .green : .red))
                .strikethrough(debt.isPaid)
            
            // Кнопка переключения выплаты
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
        formatter.locale = Locale(identifier: "en_US")
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
    @State private var isLent: Bool = true
    @State private var dueDate: Date = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    
                    HStack {
                        Text("Amount ($)")
                        Spacer()
                        TextField("0", text: $amountString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Debt Info")
                }
                
                Section {
                    Picker("Type", selection: $isLent) {
                        Text("I lent (Мне должны)").tag(true)
                        Text("I borrowed (Я должен)").tag(false)
                    }
                    .pickerStyle(.segmented)
                    
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                } header: {
                    Text("Details")
                }
            }
            .navigationTitle("New Debt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
            isLent: isLent
        )
        financeService.addDebt(debt)
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
