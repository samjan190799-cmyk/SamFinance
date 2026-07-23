import SwiftUI

/// Экран управления накопительными копилками (Goals) в премиальном дизайне.
/// Без пустого пространства сверху и с белой шторкой, уходящей до самого низа экрана.
struct GoalsView: View {
    let financeService: FinanceService
    @State private var isShowingAddSheet = false
    
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.height < 750
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "#0E0F12") // Глубокий темный фон
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Шапка
                headerView
                    .padding(.horizontal, 24)
                    .padding(.top, isSmallScreen ? 34 : 54)
                    .padding(.bottom, isSmallScreen ? 16 : 24)
                
                // Белая шторка со списком копилок
                goalsBottomSheet
            }
            .ignoresSafeArea(edges: .bottom) // Позволяет шторке уходить до низа экрана
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingAddSheet) {
            AddGoalView(financeService: financeService)
        }
    }
    
    // MARK: - Шапка
    private var headerView: some View {
        HStack {
            Text("Goals")
                .font(.system(size: isSmallScreen ? 28 : 32, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            Button {
                HapticManager.shared.impact(.light)
                isShowingAddSheet = true
            } label: {
                Text("New Goal")
                    .font(.system(size: isSmallScreen ? 11 : 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, isSmallScreen ? 12 : 16)
                    .padding(.vertical, isSmallScreen ? 6 : 8)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Шторка со списком
    private var goalsBottomSheet: some View {
        VStack(spacing: 0) {
            if financeService.goals.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.35))
                        .symbolRenderingMode(.hierarchical)
                    
                    Text("Копилок пока нет")
                        .font(.headline)
                        .foregroundColor(.black.opacity(0.6))
                    
                    Text("Создайте цель, чтобы начать копить деньги на мечту.")
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
                    VStack(spacing: 20) {
                        ForEach(financeService.goals) { goal in
                            GoalItemRowView(goal: goal, financeService: financeService)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        HapticManager.shared.trigger(.warning)
                                        withAnimation(.spring()) {
                                            financeService.deleteGoal(id: goal.id)
                                        }
                                    } label: {
                                        Label("Delete Goal", systemImage: "trash")
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

/// Компонент строки копилки с градиентной карточкой и неоновым свечением
struct GoalItemRowView: View {
    let goal: Goal
    let financeService: FinanceService
    @State private var isShowingDepositAlert = false
    @State private var depositAmountString = ""
    
    var body: some View {
        Button {
            HapticManager.shared.impact(.light)
            isShowingDepositAlert = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(goal.title)
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("\(Int(progressPercent * 100))%")
                        .font(.subheadline.bold())
                        .foregroundColor(.white.opacity(0.95))
                }
                
                Spacer()
                
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("$\(formatAmount(goal.currentAmount))")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("цель $\(formatAmount(goal.targetAmount))")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    
                    Spacer()
                    
                    // Кнопка пополнить
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Пополнить")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(Capsule())
                }
                
                // Прогресс-бар
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white)
                            .frame(width: max(0, min(geo.size.width * CGFloat(progressPercent), geo.size.width)), height: 6)
                    }
                }
                .frame(height: 6)
            }
            .padding(18)
            .frame(height: 120)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(cardGradient)
            }
            .shadow(color: Color(hex: goal.colorHex).opacity(0.35), radius: 12, x: 0, y: 8)
        }
        .alert("Пополнить копилку \(goal.title)", isPresented: $isShowingDepositAlert) {
            TextField("Сумма ($)", text: $depositAmountString)
                .keyboardType(.decimalPad)
            Button("Отмена", role: .cancel) {
                depositAmountString = ""
            }
            Button("Пополнить") {
                if let amount = Double(depositAmountString.replacingOccurrences(of: ",", with: ".")) {
                    HapticManager.shared.trigger(.success)
                    financeService.addFundsToGoal(id: goal.id, amount: amount)
                }
                depositAmountString = ""
            }
        } message: {
            Text("Введите сумму, которую хотите внести в эту копилку.")
        }
    }
    
    private var progressPercent: Double {
        guard goal.targetAmount > 0 else { return 0.0 }
        return goal.currentAmount / goal.targetAmount
    }
    
    private var cardGradient: LinearGradient {
        LinearGradient(
            colors: goal.gradientColors.map { Color(hex: $0) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// Модальный экран создания новой копилки
struct AddGoalView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    
    @State private var title: String = ""
    @State private var targetAmountString: String = ""
    @State private var selectedColorIndex = 0
    
    // Предопределенные градиенты для копилок
    let colorOptions = [
        (colorHex: "#FFD200", gradient: ["#FFE259", "#FFA751"]), // Золотой
        (colorHex: "#00F2FE", gradient: ["#00F2FE", "#4FACFE"]), // Бирюзовый
        (colorHex: "#FF2D55", gradient: ["#FF2D55", "#FF5E62"]), // Розовый
        (colorHex: "#AF52DE", gradient: ["#AF52DE", "#D100F3"])  // Фиолетовый
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Goal Title (e.g. New Car)", text: $title)
                        .textInputAutocapitalization(.sentences)
                    
                    HStack {
                        Text("Target Amount ($)")
                        Spacer()
                        TextField("0", text: $targetAmountString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Goal Details")
                }
                
                Section {
                    HStack(spacing: 16) {
                        ForEach(0..<colorOptions.count, id: \.self) { index in
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: colorOptions[index].gradient.map { Color(hex: $0) },
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if selectedColorIndex == index {
                                        Circle()
                                            .stroke(Color.white, lineWidth: 3)
                                            .shadow(radius: 4)
                                    }
                                }
                                .scaleEffect(selectedColorIndex == index ? 1.1 : 1.0)
                                .onTapGesture {
                                    HapticManager.shared.impact(.light)
                                    withAnimation(.spring()) {
                                        selectedColorIndex = index
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Select Theme")
                }
            }
            .navigationTitle("New Savings Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGoal()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }
    
    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        Double(targetAmountString.replacingOccurrences(of: ",", with: ".")) ?? 0 <= 0
    }
    
    private func saveGoal() {
        guard let targetAmount = Double(targetAmountString.replacingOccurrences(of: ",", with: ".")) else { return }
        let option = colorOptions[selectedColorIndex]
        let goal = Goal(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            targetAmount: targetAmount,
            currentAmount: 0.0,
            colorHex: option.colorHex,
            gradientColors: option.gradient
        )
        financeService.addGoal(goal)
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
