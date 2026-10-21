import SwiftUI

/// Экран настроек приложения. Позволяет переключать язык (Русский, English, Հայերեն), экспортировать информацию и сбрасывать состояние.
struct SettingsView: View {
    let financeService: FinanceService
    @State private var languageManager = LanguageManager.shared
    @State private var currencyManager = CurrencyManager.shared
    @State private var isShowingConverter = false
    @State private var isShowingDeleteAlert = false
    @State private var exportMessage: String? = nil
    @State private var purchasePromptStatus: String? = nil
    @AppStorage(AutomationKeys.autoCreateCards) private var autoCreateCards = true
    @AppStorage(AutomationKeys.skipOwnTransfers) private var skipOwnTransfers = true
    @AppStorage(AutomationKeys.ownSurnames) private var ownSurnames = ""
    @State private var hasAPIKey = AIKeyStore.key() != nil
    @State private var apiKeyInput = ""
    @State private var apiKeyError: String? = nil

    var body: some View {
        NavigationStack {
            List {
                // Секция профиля
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.white)
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
                
                // Облачный ИИ: собственный ключ Claude API
                aiKeySection

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
                
                // Автоматизация учёта
                Section {
                    Toggle("Создавать карты автоматически", isOn: $autoCreateCards)
                    Toggle("Не считать переводы между своими картами", isOn: $skipOwnTransfers)
                    HStack {
                        Text("Моя фамилия в СМС")
                        Spacer()
                        TextField("SURNAME", text: $ownSurnames)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Автоматизация")
                } footer: {
                    Text("В Быстрых командах: Автоматизация → Сообщение → отправитель (IDBank, ARCA…) → «Выполнять сразу» → действие «Распознать СМС транзакцию», в поле «Текст СМС» подставьте «Содержимое сообщения». Операция, карта и её баланс обновятся сами. Фамилию укажите латиницей, как в СМС: переводы себе не считаются доходом и расходом.")
                }

                // Подсказки покупок Apple Pay
                Section {
                    Button {
                        Task {
                            let granted = await PurchasePromptService.shared.requestAuthorization()
                            HapticManager.shared.trigger(granted ? .success : .warning)
                            purchasePromptStatus = granted ? "Уведомления включены" : "Выключены в настройках iOS"
                        }
                    } label: {
                        HStack {
                            Label("Включить подсказки покупок", systemImage: "applelogo")
                            Spacer()
                            if let status = purchasePromptStatus {
                                Text(status)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Apple Pay")
                } footer: {
                    Text("В Быстрых командах: Автоматизация → Транзакция → выберите карты → «Выполнять сразу» → действие «Записать покупку Apple Pay», подставьте Магазин и Сумму из транзакции. После оплаты придёт уведомление: расход или доход, затем категория.")
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
            .monoForm()
            .tint(Theme.accent)
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
    
    // MARK: - Ключ Claude API
    private var aiKeySection: some View {
        Section {
            if hasAPIKey {
                Label("Ключ Claude сохранён", systemImage: "checkmark.seal.fill")
                    .foregroundColor(Theme.accent)
                Button(role: .destructive) {
                    HapticManager.shared.trigger(.warning)
                    AIKeyStore.deleteKey()
                    hasAPIKey = false
                } label: {
                    Label("Удалить ключ", systemImage: "trash")
                }
            } else {
                SecureField("sk-ant-…", text: $apiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    saveAPIKey()
                } label: {
                    Label("Сохранить ключ", systemImage: "key.fill")
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let apiKeyError {
                    Text(apiKeyError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let url = URL(string: "https://console.anthropic.com/settings/keys") {
                    Link(destination: url) {
                        HStack {
                            Label("Создать ключ в консоли Anthropic", systemImage: "safari")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("ИИ-помощник")
        } footer: {
            Text("Ключ хранится в Keychain только на этом телефоне. С ключом ИИ-чат отвечает на любые вопросы, разбирает чеки, выписки и скриншоты моделью Claude Opus 5.5: вопрос, скриншоты и сводка ваших операций, карт (последние 4 цифры) и долгов отправляются в Anthropic, оплата по тарифу ключа. Банковские СМС по-прежнему распознаются на телефоне и в облако не уходят. Без ключа всё считается только на телефоне.")
        }
    }

    private func saveAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard key.hasPrefix("sk-ant-") else {
            apiKeyError = "Ключ Claude начинается с «sk-ant-». Скопируйте его из консоли Anthropic целиком."
            HapticManager.shared.trigger(.error)
            return
        }
        if AIKeyStore.setKey(key) {
            HapticManager.shared.trigger(.success)
            apiKeyInput = ""
            apiKeyError = nil
            hasAPIKey = true
        } else {
            apiKeyError = "Не получилось сохранить ключ в Keychain. Разблокируйте телефон и попробуйте ещё раз."
            HapticManager.shared.trigger(.error)
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
