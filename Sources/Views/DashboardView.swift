import SwiftUI
import Charts

/// Перечисление временных интервалов для точного фильтра дат и трат
public enum TimePeriodFilter: String, CaseIterable, Identifiable {
    case today = "Сегодня"
    case week = "Неделя"
    case month = "Месяц"
    case allTime = "Всё время"
    
    public var id: String { rawValue }
}

/// Главный экран приложения с интеллектуальным ИИ-Советником и фильтрацией трат по датам.
@MainActor
struct DashboardView: View {
    let financeService: FinanceService
    @Binding var selectedTab: Int
    @State private var isShowingAddSheet = false
    @State private var isShowingSettingsSheet = false
    @State private var isShowingConverter = false
    @State private var isShowingAIAdvisorSheet = false
    @State private var isShowingResetAlert = false
    @State private var isShowingFullChartSheet = false
    
    @State private var selectedPeriod: TimePeriodFilter = .month
    
    // Распознавание СМС
    @State private var detectedSMSTransaction: ParsedSMSTransaction? = nil
    @State private var showSMSBanner = false
    @State private var lastCheckedClipboardString = ""
    @State private var detectedBatchTransactions: [ParsedSMSTransaction] = []
    
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.height < 750
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Атмосферный неоновый фон 2026
            ZStack {
                Color(hex: "#090A0E")
                    .ignoresSafeArea()
                
                Circle()
                    .fill(Color(hex: "#00F2FE").opacity(0.12))
                    .frame(width: 260, height: 260)
                    .blur(radius: 80)
                    .offset(x: -120, y: -200)
                
                Circle()
                    .fill(Color(hex: "#7C4DFF").opacity(0.14))
                    .frame(width: 280, height: 280)
                    .blur(radius: 90)
                    .offset(x: 140, y: -150)
            }
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    headerView
                        .padding(.horizontal, 24)
                        .padding(.top, isSmallScreen ? 34 : 54)
                    
                    HStack(alignment: .center, spacing: 0) {
                        balanceSection
                        Spacer()
                        miniCardsStack
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, isSmallScreen ? 14 : 22)
                    
                    periodPickerView
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                    
                    spendingSection
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    
                    aiAdvisorBannerCard
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    
                    analyticsSection
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .padding(.bottom, isSmallScreen ? 110 : 140)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            
            if showSMSBanner, let parsed = detectedSMSTransaction {
                smsNotificationBanner(parsed: parsed)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            checkClipboardForSMS()
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddTransactionView(financeService: financeService)
        }
        .sheet(isPresented: $isShowingSettingsSheet) {
            SettingsView(financeService: financeService)
        }
        .sheet(isPresented: $isShowingConverter) {
            CurrencyConverterView()
        }
        .sheet(isPresented: $isShowingAIAdvisorSheet) {
            AIFinancialAdvisorSheet(financeService: financeService)
        }
        .sheet(isPresented: $isShowingFullChartSheet) {
            FullExpenseChartView(financeService: financeService)
        }
        .confirmationDialog(
            "Сбросить все данные?",
            isPresented: $isShowingResetAlert,
            titleVisibility: .visible
        ) {
            Button("Сбросить все транзакции и баланс", role: .destructive) {
                financeService.resetAllData()
                HapticManager.shared.trigger(.success)
            }
            Button("Отмена", role: .cancel) {
                HapticManager.shared.impact(.light)
            }
        } message: {
            Text("Это действие удалит ошибочные транзакции, очистит историю и сбросит траты в 0.")
        }
    }
    
    // MARK: - Шапка
    private var headerView: some View {
        HStack {
            Button {
                HapticManager.shared.impact(.light)
                isShowingSettingsSheet = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#00F2FE"), Color(hex: "#7C4DFF")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: isSmallScreen ? 36 : 42, height: isSmallScreen ? 36 : 42)
                        
                        Image(systemName: "person.fill")
                            .foregroundColor(.white)
                            .font(.system(size: isSmallScreen ? 15 : 17, weight: .bold))
                    }
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5))
                    .shadow(color: Color(hex: "#00F2FE").opacity(0.3), radius: 8, x: 0, y: 2)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("samvel_fin".localized)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Text("PRO Account")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "#00F2FE"))
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // Кнопка Сброса
                Button {
                    HapticManager.shared.trigger(.warning)
                    isShowingResetAlert = true
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: isSmallScreen ? 13 : 15, weight: .bold))
                        .foregroundColor(.red.opacity(0.9))
                        .frame(width: isSmallScreen ? 34 : 40, height: isSmallScreen ? 34 : 40)
                        .background(Color.red.opacity(0.14))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.red.opacity(0.3), lineWidth: 1))
                }
                
                // Конвертер
                Button {
                    HapticManager.shared.impact(.light)
                    isShowingConverter = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: isSmallScreen ? 14 : 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: isSmallScreen ? 34 : 40, height: isSmallScreen ? 34 : 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                
                // SMS Буфер
                Button {
                    HapticManager.shared.impact(.light)
                    checkClipboardForSMS()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: isSmallScreen ? 14 : 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: isSmallScreen ? 34 : 40, height: isSmallScreen ? 34 : 40)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                        
                        if showSMSBanner {
                            Circle()
                                .fill(Color(hex: "#00F2FE"))
                                .frame(width: 8, height: 8)
                                .offset(x: -2, y: 2)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Переключатель периодов времени
    private var periodPickerView: some View {
        HStack(spacing: 8) {
            ForEach(TimePeriodFilter.allCases) { period in
                Button {
                    HapticManager.shared.impact(.light)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedPeriod = period
                    }
                } label: {
                    Text(period.rawValue)
                        .font(.system(size: 12, weight: selectedPeriod == period ? .bold : .medium))
                        .foregroundColor(selectedPeriod == period ? .black : .white.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            ZStack {
                                if selectedPeriod == period {
                                    Capsule()
                                        .fill(Color.white)
                                        .shadow(color: Color.white.opacity(0.3), radius: 8, x: 0, y: 2)
                                } else {
                                    Capsule()
                                        .fill(Color.white.opacity(0.05))
                                }
                            }
                        )
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    // MARK: - Раздел баланса
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: isSmallScreen ? 8 : 12) {
            Text("total_balance".localized.uppercased())
                .font(.system(size: isSmallScreen ? 10 : 11, weight: .bold))
                .foregroundColor(Color(hex: "#A0A5B5"))
                .tracking(1.2)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                let formatted = balanceFormatted
                Text(formatted.whole)
                    .font(.system(size: isSmallScreen ? 32 : 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: Color.white.opacity(0.15), radius: 10, x: 0, y: 2)
                
                Text(formatted.fraction)
                    .font(.system(size: isSmallScreen ? 18 : 22, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "#A0A5B5"))
            }
            
            HStack(spacing: 10) {
                Button {
                    HapticManager.shared.trigger(.success)
                    isShowingAddSheet = true
                } label: {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: isSmallScreen ? 20 : 24, height: isSmallScreen ? 20 : 24)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: isSmallScreen ? 9 : 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("send".localized)
                            .font(.system(size: isSmallScreen ? 12 : 13, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, isSmallScreen ? 14 : 18)
                    .padding(.vertical, isSmallScreen ? 8 : 10)
                    .background(
                        LinearGradient(
                            colors: [Color.white, Color(hex: "#E2E8F0")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.white.opacity(0.3), radius: 8, x: 0, y: 2)
                }
                
                Button {
                    HapticManager.shared.impact(.light)
                    isShowingAddSheet = true
                } label: {
                    Text("request".localized)
                        .font(.system(size: isSmallScreen ? 12 : 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, isSmallScreen ? 14 : 18)
                        .padding(.vertical, isSmallScreen ? 8 : 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
            }
        }
    }
    
    // MARK: - Стопка мини-карт
    private var miniCardsStack: some View {
        Button {
            HapticManager.shared.trigger(.success)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                selectedTab = 2
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(hex: "#7C4DFF"), Color(hex: "#0072FF")], startPoint: .top, endPoint: .bottom))
                    .frame(width: isSmallScreen ? 40 : 48, height: isSmallScreen ? 66 : 80)
                    .offset(x: isSmallScreen ? 16 : 20, y: isSmallScreen ? 4 : 6)
                    .rotationEffect(.degrees(6))
                
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(hex: "#00F2FE"), Color(hex: "#4FACFE")], startPoint: .top, endPoint: .bottom))
                    .frame(width: isSmallScreen ? 40 : 48, height: isSmallScreen ? 66 : 80)
                    .offset(x: isSmallScreen ? 8 : 10, y: 0)
                    .rotationEffect(.degrees(-2))
                
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(hex: "#FFE259"), Color(hex: "#FFA751")], startPoint: .top, endPoint: .bottom))
                    .frame(width: isSmallScreen ? 40 : 48, height: isSmallScreen ? 66 : 80)
                    .offset(x: 0, y: isSmallScreen ? -4 : -6)
                    .rotationEffect(.degrees(-7))
            }
            .frame(width: isSmallScreen ? 60 : 70, height: isSmallScreen ? 80 : 90)
            .offset(x: isSmallScreen ? 24 : 30)
            .shadow(color: Color.black.opacity(0.4), radius: 10, x: -4, y: 4)
        }
    }
    
    // MARK: - Блок расходов за период
    private var filteredSpendingAmount: Double {
        let calendar = Calendar.current
        let now = Date()
        let expenses = financeService.transactions.filter { $0.type == .expense }
        
        switch selectedPeriod {
        case .today:
            return expenses.filter { calendar.isDateInToday($0.date) }.reduce(0) { $0 + $1.amount }
        case .week:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return expenses.filter { $0.date >= weekAgo }.reduce(0) { $0 + $1.amount }
        case .month:
            let monthAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return expenses.filter { $0.date >= monthAgo }.reduce(0) { $0 + $1.amount }
        case .allTime:
            return financeService.totalSpending
        }
    }
    
    private var spendingSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Траты (\(selectedPeriod.rawValue.lowercased()))")
                    .font(.system(size: isSmallScreen ? 11 : 12, weight: .medium))
                    .foregroundColor(Color(hex: "#A0A5B5"))
                
                Text(formatSpendingAmount(filteredSpendingAmount))
                    .font(.system(size: isSmallScreen ? 20 : 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            HStack(spacing: -8) {
                brandMiniIcon(name: "apple.logo", color: .white, bgColor: .black)
                brandMiniIcon(name: "at", color: .white, bgColor: Color(hex: "#1A1B22"))
                brandMiniIcon(name: "cart.fill", color: .white, bgColor: Color(hex: "#FF9500"))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, isSmallScreen ? 12 : 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Карточка ИИ-Советника
    private var aiAdvisorBannerCard: some View {
        Button {
            HapticManager.shared.trigger(.success)
            isShowingAIAdvisorSheet = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#7C4DFF"), Color(hex: "#00F2FE")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: Color(hex: "#7C4DFF").opacity(0.4), radius: 10, x: 0, y: 4)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("💡 ИИ-Финансовый Советник")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Глубокий анализ истории трат и персональные советы")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#00F2FE"))
            }
            .padding(16)
            .background(Color(hex: "#12141F").opacity(0.9))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "#7C4DFF").opacity(0.5), Color(hex: "#00F2FE").opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color(hex: "#7C4DFF").opacity(0.15), radius: 12, x: 0, y: 6)
        }
    }
    
    // MARK: - Секция аналитики
    private var analyticsSection: some View {
        VStack(spacing: 16) {
            DashboardLineChartCard(financeService: financeService, selectedPeriod: selectedPeriod) {
                HapticManager.shared.impact(.medium)
                isShowingFullChartSheet = true
            }
            DashboardDonutChartCard(financeService: financeService, selectedPeriod: selectedPeriod)
        }
    }
    
    private func smsNotificationBanner(parsed: ParsedSMSTransaction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "banknote.fill")
                .font(.title2)
                .foregroundColor(.green)
                .padding(10)
                .background(Color.green.opacity(0.15))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(detectedBatchTransactions.count > 1 ? "Найдено СМС в буфере: \(detectedBatchTransactions.count)" : "Найдена СМС в буфере")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.gray)
                
                Text(detectedBatchTransactions.count > 1 ? "Всего на сумму: \(CurrencyManager.shared.format(detectedBatchTransactions.reduce(0) { $0 + $1.amount }))" : "\(parsed.title) — \(parsed.type == .income ? "+" : "-")\(CurrencyManager.shared.format(parsed.amount))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Button {
                HapticManager.shared.impact(.light)
                withAnimation {
                    showSMSBanner = false
                    detectedSMSTransaction = nil
                    detectedBatchTransactions = []
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            
            Button {
                addDetectedTransaction()
            } label: {
                Text(detectedBatchTransactions.count > 1 ? "Записать все (\(detectedBatchTransactions.count))" : "Записать")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color(hex: "#1E1F22"))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 24)
        .padding(.top, isSmallScreen ? 12 : 24)
        .shadow(color: Color.black.opacity(0.5), radius: 15, x: 0, y: 10)
    }
    
    private func checkClipboardForSMS() {
        guard let clipboardString = UIPasteboard.general.string,
              !clipboardString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              clipboardString != lastCheckedClipboardString else { return }
        
        lastCheckedClipboardString = clipboardString
        
        let batch = SMSParser.parseBatch(text: clipboardString)
        if !batch.isEmpty {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                detectedBatchTransactions = batch
                detectedSMSTransaction = batch.first
                showSMSBanner = true
            }
        }
    }
    
    private func addDetectedTransaction() {
        let itemsToAdd = detectedBatchTransactions.isEmpty ? (detectedSMSTransaction != nil ? [detectedSMSTransaction!] : []) : detectedBatchTransactions
        guard !itemsToAdd.isEmpty else { return }
        
        for parsed in itemsToAdd {
            let category = financeService.categories.first(where: { $0.name == parsed.categoryName }) ?? financeService.categories[0]
            
            let transaction = Transaction(
                title: parsed.title,
                amount: parsed.amount,
                type: parsed.type,
                category: category,
                date: parsed.date ?? Date(),
                notes: "Автоматически распознано из СМС",
                brandName: parsed.brandName,
                brandIcon: category.icon,
                brandColorHex: category.colorHex
            )
            
            financeService.addTransaction(transaction)
        }
        
        HapticManager.shared.trigger(.success)
        UIPasteboard.general.string = ""
        
        withAnimation {
            showSMSBanner = false
            detectedSMSTransaction = nil
            detectedBatchTransactions = []
        }
    }
    
    private func brandMiniIcon(name: String, color: Color, bgColor: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: isSmallScreen ? 9 : 11, weight: .bold))
            .foregroundColor(color)
            .frame(width: isSmallScreen ? 24 : 28, height: isSmallScreen ? 24 : 28)
            .background(bgColor)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(hex: "#0E0F12"), lineWidth: 1.5))
    }
    
    private var balanceFormatted: (whole: String, fraction: String) {
        let balance = financeService.totalBalance
        let symbol = CurrencyManager.shared.currentCurrency.symbol
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        
        let formattedNum = formatter.string(from: NSNumber(value: balance)) ?? "\(Int(balance))"
        return ("\(symbol)\(formattedNum)", ".00")
    }
    
    private func formatSpendingAmount(_ amount: Double) -> String {
        return CurrencyManager.shared.format(amount)
    }
}

/// Выделенный под-компонент линейного графика для динамической фильтрации
@MainActor
struct DashboardLineChartCard: View {
    let financeService: FinanceService
    let selectedPeriod: TimePeriodFilter
    var onTap: (() -> Void)? = nil
    
    struct SpendingChartData: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Double
    }
    
    private var chartData: [SpendingChartData] {
        let expenses = financeService.transactions.filter { $0.type == .expense }
        let calendar = Calendar.current
        var dateMap: [Date: Double] = [:]
        let daysCount = selectedPeriod == .today ? 1 : (selectedPeriod == .week ? 7 : 30)
        
        for i in 0..<daysCount {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let startOfDay = calendar.startOfDay(for: date)
                dateMap[startOfDay] = 0.0
            }
        }
        
        for transaction in expenses {
            let startOfDay = calendar.startOfDay(for: transaction.date)
            if dateMap[startOfDay] != nil {
                dateMap[startOfDay]? += transaction.amount
            }
        }
        
        return dateMap.map { SpendingChartData(date: $0.key, amount: $0.value) }
            .sorted(by: { $0.date < $1.date })
    }
    
    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("График расходов (\(selectedPeriod.rawValue.lowercased()))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text("Открыть")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#00F2FE"))
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#00F2FE"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#00F2FE").opacity(0.12))
                    .clipShape(Capsule())
                }
                
                if chartData.isEmpty || financeService.totalSpending == 0 {
                    emptyChartPlaceholder
                } else {
                    makeLineChart()
                }
            }
            .padding(18)
            .background(Color.white.opacity(0.04))
            .cornerRadius(24)
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    
    private func makeLineChart() -> some View {
        Chart {
            ForEach(chartData) { item in
                AreaMark(
                    x: .value("Дата", item.date, unit: .day),
                    y: .value("Траты", item.amount)
                )
                .foregroundStyle(LinearGradient(colors: [Color(hex: "#00F2FE").opacity(0.25), Color(hex: "#00F2FE").opacity(0.0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
                
                LineMark(
                    x: .value("Дата", item.date, unit: .day),
                    y: .value("Траты", item.amount)
                )
                .foregroundStyle(Color(hex: "#00F2FE"))
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: selectedPeriod == .month ? 7 : (selectedPeriod == .week ? 2 : 1))) { value in
                AxisValueLabel(format: .dateTime.day().month(.twoDigits))
                    .foregroundStyle(Color.gray.opacity(0.8))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let doubleVal = value.as(Double.self) {
                        Text(formatCompactNumber(doubleVal))
                            .font(.caption2)
                            .foregroundStyle(Color.gray.opacity(0.8))
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(Color.white.opacity(0.06))
            }
        }
        .frame(height: 160)
    }
    
    private func formatCompactNumber(_ number: Double) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", number / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.0fK", number / 1_000)
        } else {
            return "\(Int(number))"
        }
    }
    
    private var emptyChartPlaceholder: some View {
        VStack {
            Spacer()
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.1))
            Text("no_chart_data".localized)
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 130)
    }
}

/// Выделенный под-компонент круговой диаграммы
@MainActor
struct DashboardDonutChartCard: View {
    let financeService: FinanceService
    let selectedPeriod: TimePeriodFilter
    
    struct CategorySpendingData: Identifiable {
        let id = UUID()
        let category: String
        let amount: Double
        let color: Color
    }
    
    private var categoryData: [CategorySpendingData] {
        let calendar = Calendar.current
        let now = Date()
        
        let expenses = financeService.transactions.filter { exp in
            guard exp.type == .expense else { return false }
            switch selectedPeriod {
            case .today:
                return calendar.isDateInToday(exp.date)
            case .week:
                let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
                return exp.date >= weekAgo
            case .month:
                let monthAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
                return exp.date >= monthAgo
            case .allTime:
                return true
            }
        }
        
        var categoryMap: [String: Double] = [:]
        var colorMap: [String: String] = [:]
        
        for transaction in expenses {
            categoryMap[transaction.category.name, default: 0.0] += transaction.amount
            colorMap[transaction.category.name] = transaction.category.colorHex
        }
        
        return categoryMap.map { key, value in
            CategorySpendingData(
                category: key,
                amount: value,
                color: Color(hex: colorMap[key] ?? "#FFFFFF")
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Категории (\(selectedPeriod.rawValue.lowercased()))")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
            
            if categoryData.isEmpty {
                emptyChartPlaceholder
            } else {
                HStack(spacing: 20) {
                    makeDonutChart()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(categoryData.prefix(4)) { item in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 8, height: 8)
                                Text(item.category)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(CurrencyManager.shared.format(item.amount))
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.04))
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.04), lineWidth: 1))
    }
    
    private func makeDonutChart() -> some View {
        Chart {
            ForEach(categoryData) { item in
                SectorMark(
                    angle: .value("spending".localized, item.amount),
                    innerRadius: .ratio(0.65),
                    angularInset: 2
                )
                .cornerRadius(4)
                .foregroundStyle(item.color)
            }
        }
        .frame(width: 140, height: 140)
    }
    
    private var emptyChartPlaceholder: some View {
        VStack {
            Spacer()
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.1))
            Text("no_chart_data".localized)
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 130)
    }
}

/// Экран ИИ-Советника с персональными рекомендациями
@MainActor
struct AIFinancialAdvisorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    
    private var insights: [AIFinancialInsight] {
        AIService.shared.generateInsights(financeService: financeService)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0E0F12")
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [Color(hex: "#8E2DE2"), Color(hex: "#4A00E0")], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 50, height: 50)
                                Image(systemName: "sparkles")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("SamFinance AI Advisor")
                                    .font(.title3.bold())
                                    .foregroundColor(.white)
                                Text("Умный финансовый помощник")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal, 4)
                        
                        Text("Персональный анализ бюджета:")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.top, 4)
                        
                        VStack(spacing: 14) {
                            ForEach(insights) { insight in
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: insight.iconName)
                                        .font(.title3)
                                        .foregroundColor(colorForType(insight.type))
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(insight.title)
                                            .font(.subheadline.bold())
                                            .foregroundColor(.white)
                                        
                                        Text(insight.message)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.75))
                                    }
                                    Spacer()
                                }
                                .padding(16)
                                .background(Color(hex: "#17181A"))
                                .cornerRadius(18)
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(colorForType(insight.type).opacity(0.2), lineWidth: 1))
                            }
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("ИИ-Советник")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func colorForType(_ type: AIFinancialInsight.InsightType) -> Color {
        switch type {
        case .positive: return .green
        case .warning: return .orange
        case .info: return Color(hex: "#00F2FE")
        }
    }
}

/// Полноэкранный/расширенный детальный график расходов с интерактивными точками и историей операций
@MainActor
struct FullExpenseChartView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    @State private var selectedPeriod: TimePeriodFilter = .month
    @State private var rawSelectedDate: Date? = nil
    
    struct SpendingPoint: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Double
    }
    
    private var chartPoints: [SpendingPoint] {
        let expenses = financeService.transactions.filter { $0.type == .expense }
        let calendar = Calendar.current
        var dateMap: [Date: Double] = [:]
        let daysCount = selectedPeriod == .today ? 1 : (selectedPeriod == .week ? 7 : 30)
        
        for i in 0..<daysCount {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let startOfDay = calendar.startOfDay(for: date)
                dateMap[startOfDay] = 0.0
            }
        }
        
        for transaction in expenses {
            let startOfDay = calendar.startOfDay(for: transaction.date)
            if dateMap[startOfDay] != nil {
                dateMap[startOfDay]? += transaction.amount
            }
        }
        
        return dateMap.map { SpendingPoint(date: $0.key, amount: $0.value) }
            .sorted(by: { $0.date < $1.date })
    }
    
    private var totalSpendingForPeriod: Double {
        chartPoints.reduce(0) { $0 + $1.amount }
    }
    
    private var selectedPoint: SpendingPoint? {
        guard let rawSelectedDate else { return nil }
        let calendar = Calendar.current
        return chartPoints.first { calendar.isDate($0.date, inSameDayAs: rawSelectedDate) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0E0F12")
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Переключатель периода
                        HStack(spacing: 8) {
                            ForEach(TimePeriodFilter.allCases) { period in
                                Button {
                                    HapticManager.shared.impact(.light)
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        selectedPeriod = period
                                    }
                                } label: {
                                    Text(period.rawValue)
                                        .font(.system(size: 13, weight: selectedPeriod == period ? .bold : .medium))
                                        .foregroundColor(selectedPeriod == period ? .black : .white.opacity(0.8))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selectedPeriod == period ? Color.white : Color.white.opacity(0.08))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.top, 8)
                        
                        // Заголовок суммы
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Всего потрачено (\(selectedPeriod.rawValue.lowercased()))")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Text(CurrencyManager.shared.format(totalSpendingForPeriod))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        
                        // Выбранная дата на графике
                        if let selectedPoint {
                            HStack {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundColor(Color(hex: "#00F2FE"))
                                Text(formatDate(selectedPoint.date))
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                Spacer()
                                Text(CurrencyManager.shared.format(selectedPoint.amount))
                                    .font(.headline.bold())
                                    .foregroundColor(Color(hex: "#00F2FE"))
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#00F2FE").opacity(0.3), lineWidth: 1))
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        // Большой детальный график
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Динамика расходов")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Chart {
                                ForEach(chartPoints) { item in
                                    AreaMark(
                                        x: .value("Дата", item.date, unit: .day),
                                        y: .value("Траты", item.amount)
                                    )
                                    .foregroundStyle(LinearGradient(
                                        colors: [Color(hex: "#00F2FE").opacity(0.35), Color(hex: "#00F2FE").opacity(0.0)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                                    .interpolationMethod(.catmullRom)
                                    
                                    LineMark(
                                        x: .value("Дата", item.date, unit: .day),
                                        y: .value("Траты", item.amount)
                                    )
                                    .foregroundStyle(Color(hex: "#00F2FE"))
                                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .interpolationMethod(.catmullRom)
                                    
                                    if let selectedPoint, Calendar.current.isDate(item.date, inSameDayAs: selectedPoint.date) {
                                        RuleMark(x: .value("Selected", item.date))
                                            .foregroundStyle(Color.white.opacity(0.4))
                                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                        
                                        PointMark(
                                            x: .value("Selected", item.date),
                                            y: .value("SelectedVal", item.amount)
                                        )
                                        .symbolSize(100)
                                        .foregroundStyle(Color.white)
                                    }
                                }
                            }
                            .chartXSelection(value: $rawSelectedDate)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: selectedPeriod == .month ? 6 : 2)) { value in
                                    AxisValueLabel(format: .dateTime.day().month(.twoDigits))
                                        .foregroundStyle(Color.gray)
                                }
                            }
                            .chartYAxis {
                                AxisMarks { value in
                                    AxisValueLabel {
                                        if let doubleVal = value.as(Double.self) {
                                            Text(formatCompactNumber(doubleVal))
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                        .foregroundStyle(Color.white.opacity(0.06))
                                }
                            }
                            .frame(height: 250)
                        }
                        .padding(18)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(24)
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.06), lineWidth: 1))
                        
                        // Список транзакций за период
                        VStack(alignment: .leading, spacing: 14) {
                            Text("История расходов за период")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            let periodExpenses = transactionsForPeriod
                            if periodExpenses.isEmpty {
                                Text("Нет операций за этот период")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .padding(.vertical, 10)
                            } else {
                                ForEach(periodExpenses) { t in
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .fill(Color(hex: t.category.colorHex).opacity(0.2))
                                                .frame(width: 42, height: 42)
                                            Image(systemName: t.category.icon)
                                                .font(.system(size: 18))
                                                .foregroundColor(Color(hex: t.category.colorHex))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(t.title)
                                                .font(.subheadline.bold())
                                                .foregroundColor(.white)
                                            Text(formatDate(t.date))
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        
                                        Spacer()
                                        
                                        Text("-\(CurrencyManager.shared.format(t.amount))")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.red.opacity(0.9))
                                    }
                                    .padding(12)
                                    .background(Color.white.opacity(0.03))
                                    .cornerRadius(16)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Детальный график расходов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var transactionsForPeriod: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        return financeService.transactions.filter { t in
            guard t.type == .expense else { return false }
            switch selectedPeriod {
            case .today:
                return calendar.isDateInToday(t.date)
            case .week:
                let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
                return t.date >= weekAgo
            case .month:
                let monthAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
                return t.date >= monthAgo
            case .allTime:
                return true
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMMM yyyy"
        return df.string(from: date)
    }
    
    private func formatCompactNumber(_ number: Double) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", number / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.0fK", number / 1_000)
        } else {
            return "\(Int(number))"
        }
    }
}
