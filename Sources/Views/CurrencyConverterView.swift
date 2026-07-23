import SwiftUI

/// Экран Онлайн Конвертера Валют с актуальными курсами валют ЦБ
struct CurrencyConverterView: View {
    @Environment(\.dismiss) private var dismiss
    
    private var currencyService: CurrencyService { CurrencyService.shared }
    private var currencyManager: CurrencyManager { CurrencyManager.shared }
    
    @State private var amountString: String = "10000"
    @State private var sourceCurrency: AppCurrency = .amd
    @State private var targetCurrency: AppCurrency = .rub
    
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.height < 750
    }
    
    /// Результат конвертации
    private var convertedResult: Double {
        let amount = Double(amountString.replacingOccurrences(of: ",", with: ".")) ?? 0
        return currencyService.convert(amount: amount, from: sourceCurrency, to: targetCurrency)
    }
    
    /// Прямой курс 1 единицы
    private var unitRate: Double {
        return currencyService.getDirectRate(from: sourceCurrency, to: targetCurrency)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0E0F12")
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Карточка ввода суммы и выбора валюты
                    VStack(spacing: 16) {
                        HStack {
                            Text("Исходная сумма")
                                .font(.caption.bold())
                                .foregroundColor(.gray)
                            Spacer()
                            
                            Picker("", selection: $sourceCurrency) {
                                ForEach(AppCurrency.allCases) { curr in
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
                    
                    // Кнопка реверса валют
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
                    
                    // Карточка вывода результата
                    VStack(spacing: 16) {
                        HStack {
                            Text("Результат конвертации")
                                .font(.caption.bold())
                                .foregroundColor(.gray)
                            Spacer()
                            
                            Picker("", selection: $targetCurrency) {
                                ForEach(AppCurrency.allCases) { curr in
                                    Text("\(curr.flagIcon) \(curr.rawValue)").tag(curr)
                                }
                            }
                            .tint(.white)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        
                        HStack {
                            Text(formatResult(convertedResult))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                            Spacer()
                            Text(targetCurrency.symbol)
                                .font(.title.bold())
                                .foregroundColor(.gray)
                        }
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        HStack {
                            Text("1 \(sourceCurrency.rawValue) = \(formatRate(unitRate)) \(targetCurrency.symbol)")
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
                    
                    // Таблица актуальных курсов
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Курсы валют (относительно 1 USD)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 4)
                        
                        VStack(spacing: 8) {
                            ForEach(AppCurrency.allCases) { curr in
                                HStack {
                                    Text("\(curr.flagIcon) \(curr.displayName)")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("\(formatRate(currencyService.exchangeRates[curr] ?? 1.0)) \(curr.symbol)")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.top, 8)
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
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
    
    private func formatResult(_ val: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: val)) ?? "\(val)"
    }
    
    private func formatRate(_ val: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSNumber(value: val)) ?? "\(val)"
    }
}
