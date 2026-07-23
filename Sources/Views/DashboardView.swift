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
            Color(hex: "#0E0F12")
                .ignoresSafeArea()
            
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
                    .padding(.top, isSmallScreen ? 12 : 20)
                    
                    periodPickerView
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    
                    spendingSection
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                    
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
    }
    
    // MARK: - Шапка
    private var headerView: some View {
        HStack {
            Button {
                HapticManager.shared.impact(.light)
                isShowingSettingsSheet = true
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#FFE259"), Color(hex: "#FFA751")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: isSmallScreen ? 34 : 40, height: isSmallScreen ? 34 : 40)
                    
                    Image(systemName: "person.fill")
                        .foregroundColor(.white)
                        .font(.system(size: isSmallScreen ? 15 : 18))
                }
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button {
                    HapticManager.shared.impact(.light)
                    isShowingConverter = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: isSmallScreen ? 14 : 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: isSmallScreen ? 34 : 40, height: isSmallScreen ? 34 : 40)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                
                Button {
                    HapticManager.shared.impact(.light)
                    checkClipboardForSMS()
                } label: {
                    Image(systemName: "bell")
                        .font(.system(size: isSmallScreen ? 16 : 18))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: isSmallScreen ? 34 : 40, height: isSmallScreen ? 34 : 40)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
            }
        }
    }
    
    // MARK: - Переключатель периодов времени (Сегодня, Неделя, Месяц, Всё время)
    private var periodPickerView: some View {
        HStack(spacing: 6) {
            ForEach(TimePeriodFilter.allCases) { period in
                Button {
                    HapticManager.shared.impact(.light)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedPeriod = period
                    }
                } label: {
                    Text(period.rawValue)
                        .font(.system(size: 12, weight: selectedPeriod == period ? .bold : .medium))
                        .foregroundColor(selectedPeriod == period ? .black : .white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selectedPeriod == period ? Color.white : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    // MARK: - Раздел баланса
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: isSmallScreen ? 6 : 10) {
            Text("total_balance".localized)
                .font(.system(size: isSmallScreen ? 12 : 14))
                .foregroundColor(.gray)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                let formatted = balanceFormatted
                Text(formatted.whole)
                    .font(.system(size: isSmallScreen ? 30 : 38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(formatted.fraction)
                    .font(.system(size: isSmallScreen ? 18 : 22, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
            }
            
            HStack(spacing: 8) {
                Button {
                    HapticManager.shared.trigger(.success)
                    isShowingAddSheet = true
                } label: {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: isSmallScreen ? 18 : 22, height: isSmallScreen ? 18 : 22)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: isSmallScreen ? 8 : 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("send".localized)
                            .font(.system(size: isSmallScreen ? 11 : 13, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, isSmallScreen ? 10 : 14)
                    .padding(.vertical, isSmallScreen ? 6 : 8)
                    .background(Color.white)
                    .clipShape(Capsule())
                }
                
                Button {
                    HapticManager.shared.impact(.light)
                    isShowingAddSheet = true
                } label: {
                    Text("request".localized)
                        .font(.system(size: isSmallScreen ? 11 : 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, isSmallScreen ? 12 : 16)
                        .padding(.vertical, isSmallScreen ? 6 : 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
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
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(hex: "#00C6FF"), Color(hex: "#0072FF")], startPoint: .top, endPoint: .bottom))
                    .frame(width: isSmallScreen ? 38 : 46, height: isSmallScreen ? 64 : 78)
                    .offset(x: isSmallScreen ? 16 : 20, y: isSmallScreen ? 4 : 6)
                    .rotationEffect(.degrees(4))
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(hex: "#00F2FE"), Color(hex: "#4FACFE")], startPoint: .top, endPoint: .bottom))
                    .frame(width: isSmallScreen ? 38 : 46, height: isSmallScreen ? 64 : 78)
                    .offset(x: isSmallScreen ? 8 : 10, y: 0)
                    .rotationEffect(.degrees(-2))
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(hex: "#FFE259"), Color(hex: "#FFA751")], startPoint: .top, endPoint: .bottom))
                    .frame(width: isSmallScreen ? 38 : 46, height: isSmallScreen ? 64 : 78)
                    .offset(x: 0, y: isSmallScreen ? -4 : -6)
                    .rotationEffect(.degrees(-6))
            }
            .frame(width: isSmallScreen ? 60 : 70, height: isSmallScreen ? 80 : 90)
            .offset(x: isSmallScreen ? 24 : 30)
            .shadow(color: Color.black.opacity(0.35), radius: 6, x: -3, y: 3)
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Траты (\(selectedPeriod.rawValue.lowercased()))")
                    .font(.system(size: isSmallScreen ? 11 : 13))
                    .foregroundColor(.gray)
                
                Text(formatSpendingAmount(filteredSpendingAmount))
                    .font(.system(size: isSmallScreen ? 18 : 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            HStack(spacing: -8) {
                brandMiniIcon(name: "apple.logo", color: .white, bgColor: .black)
                brandMiniIcon(name: "at", color: .white, bgColor: .black)
                brandMiniIcon(name: "calendar", color: .white, bgColor: Color(hex: "#34C759"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isSmallScreen ? 10 : 16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        }
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
                                colors: [Color(hex: "#8E2DE2"), Color(hex: "#4A00E0")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("💡 ИИ-Финансовый Советник")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Глубокий анализ истории трат и умные советы")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .background(Color(hex: "#17181A"))
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.purple.opacity(0.25), lineWidth: 1))
        }
    }
    
    // MARK: - Секция аналитики
    private var analyticsSection: some View {
        VStack(spacing: 16) {
            DashboardLineChartCard(financeService: financeService, selectedPeriod: selectedPeriod)
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
        VStack(alignment: .leading, spacing: 14) {
            Text("График расходов (\(selectedPeriod.rawValue.lowercased()))")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
            
            if chartData.isEmpty || financeService.totalSpending == 0 {
                emptyChartPlaceholder
            } else {
                makeLineChart()
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.04))
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.04), lineWidth: 1))
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
            AxisMarks(values: .stride(by: .day, count: selectedPeriod == .month ? 5 : 1)) { value in
                AxisValueLabel(format: .dateTime.day().month())
                    .foregroundStyle(Color.gray.opacity(0.8))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel()
                    .foregroundStyle(Color.gray.opacity(0.8))
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(Color.white.opacity(0.06))
            }
        }
        .frame(height: 160)
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
