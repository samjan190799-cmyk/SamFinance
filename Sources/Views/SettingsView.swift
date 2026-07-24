import SwiftUI

/// Экран настроек приложения. Позволяет переключать язык (Русский, English, Հայերեն), экспортировать информацию и сбрасывать состояние.
struct SettingsView: View {
    let financeService: FinanceService
    @State private var languageManager = LanguageManager.shared
    @State private var currencyManager = CurrencyManager.shared
    @State private var isShowingConverter = false
    @State private var isShowingDeleteAlert = false
    @State private var exportMessage: String? = nil
    
    var body: some View {
        NavigationStack {
            List {
                // Секция профиля
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.accentColor)
                            .symbolRenderingMode(.hierarchical)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("user_name".localized)
                                .font(.headline)
                            Text("tariff".localized)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("profile".localized)
                }
                
                // Секция предпочтений и выбора языка и валюты
                Section {
                    Picker(selection: $languageManager.currentLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text("\(lang.flagIcon)  \(lang.displayName)")
                                .tag(lang)
                        }
                    } label: {
                        Label("app_language".localized, systemImage: "globe")
                    }
                    .onChange(of: languageManager.currentLanguage) { _, _ in
                        HapticManager.shared.selection()
                    }
                    
                    Picker(selection: $currencyManager.currentCurrency) {
                        ForEach(AppCurrency.allCases) { curr in
                            Text("\(curr.symbol)  \(curr.displayName)")
                                .tag(curr)
                        }
                    } label: {
                        Label("main_currency".localized, systemImage: "dollarsign.circle.fill")
                    }
                    .onChange(of: currencyManager.currentCurrency) { _, _ in
                        HapticManager.shared.selection()
                    }
                    
                    Button {
                        HapticManager.shared.impact(.light)
                        isShowingConverter = true
                    } label: {
                        HStack {
                            Label("Онлайн конвертер валют", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button {
                        HapticManager.shared.trigger(.success)
                        exportDataToClipboard()
                    } label: {
                        HStack {
                            Label("export_data".localized, systemImage: "doc.arrow.up.fill")
                            Spacer()
                            Text(exportMessage ?? "CSV")
                                .foregroundColor(exportMessage != nil ? .green : .secondary)
                        }
                    }
                } header: {
                    Text("preferences".localized)
                }
                
                // Авто-импорт СМС в фоне
                Section {
                    Button {
                        if let url = URL(string: "shortcuts://") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Label("Фоновые команды СМС (Siri Shortcuts)", systemImage: "bolt.horizontal.fill")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Авто-импорт СМС")
                } footer: {
                    Text("В Быстрых командах iOS добавьте правило: При получении СМС -> вызывать ProcessSMSIntent для автозаписи в фоне.")
                }
                
                // Опасная зона
                Section {
                    Button(role: .destructive) {
                        HapticManager.shared.trigger(.warning)
                        isShowingDeleteAlert = true
                    } label: {
                        Label("reset_data".localized, systemImage: "trash.fill")
                    }
                } header: {
                    Text("danger_zone".localized)
                } footer: {
                    Text("reset_footer".localized)
                }
            }
            .sheet(isPresented: $isShowingConverter) {
                CurrencyConverterView()
            }
            .confirmationDialog(
                "reset_data".localized,
                isPresented: $isShowingDeleteAlert,
                titleVisibility: .visible
            ) {
                Button("reset_data".localized, role: .destructive) {
                    resetAllData()
                }
                Button("Cancel", role: .cancel) {
                    HapticManager.shared.impact(.light)
                }
            }
        }
    }
    
    private func exportDataToClipboard() {
        var csvText = "Date,Type,Category,Title,Amount\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        for t in financeService.transactions {
            let dateStr = formatter.string(from: t.date)
            csvText += "\(dateStr),\(t.type.rawValue),\(t.category.name),\(t.title),\(t.amount)\n"
        }
        
        UIPasteboard.general.string = csvText
        withAnimation {
            exportMessage = "Copied!"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            exportMessage = nil
        }
    }
    
    private func resetAllData() {
        financeService.resetAllData()
        HapticManager.shared.trigger(.success)
    }
}
