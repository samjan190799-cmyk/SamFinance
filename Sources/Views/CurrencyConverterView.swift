import SwiftUI

/// Экран Онлайн Конвертера Валют с актуальными курсами валют ЦБ
@MainActor
struct CurrencyConverterView: View {
    @Environment(\.dismiss) private var dismiss
    
    private var currencyService: CurrencyService { CurrencyService.shared }
    private var currencyManager: CurrencyManager { CurrencyManager.shared }
    
    @State private var amountString: String = "10000"
    @State private var sourceCurrency: AppCurrency = .amd
    @State private var targetCurrency: AppCurrency = .rub
    
    /// Результат конвертации
    private var convertedResultText: String {
        let amount = Double(amountString.replacingOccurrences(of: ",", with: ".")) ?? 0
        let val = currencyService.convert(amount: amount, from: sourceCurrency, to: targetCurrency)
        return formatNumber(val)
    }
    
    /// Прямой курс 1 единицы
    private var unitRateText: String {
        let val = currencyService.getDirectRate(from: sourceCurrency, to: targetCurrency)
        return formatRateNumber(val)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0E0F12")
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        sourceInputCard
                        swapButton
                        targetResultCard
                        ratesTableSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Конвертер валют")
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
    
    // MARK: - Карточка ввода исходной суммы
    private var sourceInputCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Исходная сумма")
                    .font(.caption.bold())
                    .foregroundColor(.gray)
                Spacer()
                
                Picker("", selection: $sourceCurrency) {
                    ForEach(AppCurrency.allCases, id: \.self) { curr in
                        Text("\(curr.flagIcon) \(curr.rawValue)").tag(curr)
                    }
                }
                .tint(.white)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
            
            TextField("0", text: $amountString)
                .keyboardType(.decimalPad)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(20)
        .background(Color(hex: "#17181A"))
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
    
    // MARK: - Кнопка реверса валют
    private var swapButton: some View {
        Button {
            HapticManager.shared.impact(.medium)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                let temp = sourceCurrency
                sourceCurrency = targetCurrency
                targetCurrency = temp
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 44, height: 44)
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
            }
            .shadow(color: Color.white.opacity(0.2), radius: 8, x: 0, y: 4)
        }
    }
    
    // MARK: - Карточка вывода результата
    private var targetResultCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Результат конвертации")
                    .font(.caption.bold())
                    .foregroundColor(.gray)
                Spacer()
                
                Picker("", selection: $targetCurrency) {
                    ForEach(AppCurrency.allCases, id: \.self) { curr in
                        Text("\(curr.flagIcon) \(curr.rawValue)").tag(curr)
                    }
                }
                .tint(.white)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
            
            HStack {
                Text(convertedResultText)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
                Spacer()
                Text(targetCurrency.symbol)
                    .font(.title.bold())
                    .foregroundColor(.gray)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            HStack {
                Text("1 \(sourceCurrency.rawValue) = \(unitRateText) \(targetCurrency.symbol)")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                if currencyService.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button {
                        currencyService.fetchLatestRates()
                        HapticManager.shared.trigger(.success)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Обновить")
                        }
                        .font(.caption2.bold())
                        .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(hex: "#17181A"))
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
    
    // MARK: - Таблица курсов валют
    private var ratesTableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Курсы валют (относительно 1 USD)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.gray)
                .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
                ForEach(AppCurrency.allCases, id: \.self) { curr in
                    let rateVal = currencyService.exchangeRates[curr] ?? 1.0
                    HStack {
                        Text("\(curr.flagIcon) \(curr.displayName)")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(formatRateNumber(rateVal)) \(curr.symbol)")
                            .font(.subheadline.bold())
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private func formatNumber(_ val: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: val)) ?? "\(val)"
    }
    
    private func formatRateNumber(_ val: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSNumber(value: val)) ?? "\(val)"
    }
}
