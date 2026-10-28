import SwiftUI

/// Экран настроек приложения. Позволяет переключать язык (Русский, English, Հայերեն), экспортировать информацию и сбрасывать состояние.
struct SettingsView: View {
    let financeService: FinanceService
    @State private var selectedLanguage = AppLanguage.selected
    @State private var isShowingLanguageAlert = false
    @State private var currencyManager = CurrencyManager.shared
    @State private var isShowingConverter = false
    @State private var isShowingDeleteAlert = false
    @State private var exportMessage: String? = nil
    @State private var purchasePromptStatus: String? = nil
    @AppStorage(AutomationKeys.autoCreateCards) private var autoCreateCards = true
    @AppStorage(AutomationKeys.skipOwnTransfers) private var skipOwnTransfers = true
    @AppStorage(AutomationKeys.ownSurnames) private var ownSurnames = ""
    @AppStorage(AIProvider.storageKey) private var providerRaw = AIProvider.claude.rawValue
    @State private var hasAPIKey = AIKeyStore.key(for: AIProvider.selected) != nil
    @State private var apiKeyInput = ""
    @State private var apiKeyError: String? = nil
    @State private var modelInput = AIProvider.selected.customModel ?? ""
    @State private var isCheckingConnection = false
    @State private var connectionResult: AIConnectionCheck.Outcome? = nil

    /// Выбранный облачный ИИ
    private var provider: AIProvider { AIProvider(rawValue: providerRaw) ?? .claude }

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
                        
                        Text("user_name".localized)
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("profile".localized)
                }
                
                // Секция предпочтений и выбора языка и валюты
                Section {
                    Picker(selection: $selectedLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName)
                                .tag(lang)
                        }
                    } label: {
                        Label("app_language".localized, systemImage: "globe")
                    }
                    .onChange(of: selectedLanguage) { _, newValue in
                        guard newValue != AppLanguage.selected else { return }
                        AppLanguage.select(newValue)
                        HapticManager.shared.selection()
                        isShowingLanguageAlert = true
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
                
                // Облачный ИИ: Claude, ChatGPT или Gemini с собственным ключом
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

                // Напоминания о сроках долгов, копилок и карт
                ReminderSettingsSection(financeService: financeService)

                // Подсказки покупок Apple Pay
                Section {
                    Button {
                        Task {
                            let granted = await PurchasePromptService.shared.requestAuthorization()
                            HapticManager.shared.trigger(granted ? .success : .warning)
                            purchasePromptStatus = granted ? String(localized: "Уведомления включены") : String(localized: "Выключены в настройках iOS")
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

                // О приложении: политика конфиденциальности и версия
                Section {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label(String(localized: "Политика конфиденциальности"), systemImage: "hand.raised.fill")
                    }
                    HStack {
                        Label(String(localized: "Версия"), systemImage: "info.circle")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text(String(localized: "О приложении"))
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
            .alert(selectedLanguage.string("Язык изменится после перезапуска"), isPresented: $isShowingLanguageAlert) {
                Button(selectedLanguage.string("Понятно")) {}
            } message: {
                Text(selectedLanguage.string("Закройте Hashiv (смахните его вверх в списке приложений) и откройте снова."))
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
    
    /// Версия и номер сборки для обращения в поддержку
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Облачный ИИ
    private var aiKeySection: some View {
        Section {
            Picker(selection: $providerRaw) {
                ForEach(AIProvider.allCases) { item in
                    Text(item.displayName).tag(item.rawValue)
                }
            } label: {
                Label("Какой ИИ", systemImage: "sparkles")
            }
            .onChange(of: providerRaw) { _, _ in
                HapticManager.shared.selection()
                hasAPIKey = AIKeyStore.key(for: provider) != nil
                apiKeyInput = ""
                apiKeyError = nil
                modelInput = provider.customModel ?? ""
                connectionResult = nil
            }

            if hasAPIKey {
                Label("Ключ \(provider.displayName) сохранён", systemImage: "checkmark.seal.fill")
                    .foregroundColor(Theme.accent)
                Button {
                    checkConnection()
                } label: {
                    HStack {
                        Label("Проверить подключение", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        if isCheckingConnection {
                            ProgressView()
                        }
                    }
                }
                .disabled(isCheckingConnection)
                if let connectionResult {
                    Text(connectionResult.text)
                        .font(.caption)
                        .foregroundColor(connectionResult.isWorking ? Theme.accent : .secondary)
                }
                Button(role: .destructive) {
                    HapticManager.shared.trigger(.warning)
                    AIKeyStore.deleteKey(for: provider)
                    provider.setConsent(false)
                    hasAPIKey = false
                    connectionResult = nil
                } label: {
                    Label("Удалить ключ", systemImage: "trash")
                }
            } else {
                SecureField(provider.keyPlaceholder, text: $apiKeyInput)
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
                Link(destination: provider.consoleURL) {
                    HStack {
                        Label(provider.consoleLinkTitle, systemImage: "safari")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack {
                Text("Модель")
                Spacer()
                TextField(provider.defaultModel, text: $modelInput)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.secondary)
                    .keyboardType(.asciiCapable)
                    .onChange(of: modelInput) { _, value in
                        // Пробелы и длинные тире, которые ставит клавиатура, убираются сразу: поле показывает то, что уйдёт сервису
                        let cleaned = AIProvider.normalizedModel(value)
                        if cleaned != value {
                            modelInput = cleaned
                            return
                        }
                        provider.setCustomModel(cleaned)
                        connectionResult = nil
                    }
            }
        } header: {
            Text("ИИ-помощник")
        } footer: {
            Text(aiFooter)
        }
    }

    private var aiFooter: String {
        var text = String(localized: "Ключ каждого сервиса хранится в Keychain только на этом телефоне. С ключом ИИ-чат отвечает на любые вопросы, разбирает чеки, выписки и скриншоты моделью \(provider.model): вопрос, скриншоты и сводка ваших операций, карт (последние 4 цифры), долгов, копилок и напоминаний отправляются в \(provider.company), оплата по тарифу ключа.")
        if provider == .openAI {
            text += " " + String(localized: "Нужен ключ API с platform.openai.com: подписка ChatGPT для него не подходит.")
        }
        text += " " + String(localized: "Перед первой отправкой приложение спросит разрешение; оно сбрасывается, когда вы удаляете ключ.")
        text += " " + String(localized: "Банковские СМС по-прежнему распознаются на телефоне и в облако не уходят. Без ключа всё считается только на телефоне.")
        text += " " + String(localized: "Поле «Модель» можно оставить пустым: тогда используется \(provider.defaultModel).")
        return text
    }

    /// Бесплатный запрос сведений о модели: показывает, достижим ли сервис, принят ли ключ и доступна ли модель
    private func checkConnection() {
        guard !isCheckingConnection, let key = AIKeyStore.key(for: provider) else { return }
        let checked = provider
        isCheckingConnection = true
        connectionResult = nil
        Task {
            let outcome = await AIConnectionCheck.run(provider: checked, apiKey: key)
            HapticManager.shared.trigger(outcome.isWorking ? .success : .error)
            // Пока шла проверка, мог смениться сервис: чужой результат не показываем
            if checked == provider {
                connectionResult = outcome
            }
            isCheckingConnection = false
        }
    }

    private func saveAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard provider.isPlausibleKey(key) else {
            apiKeyError = provider.keyFormatHint
            HapticManager.shared.trigger(.error)
            return
        }
        if AIKeyStore.setKey(key, for: provider) {
            HapticManager.shared.trigger(.success)
            apiKeyInput = ""
            apiKeyError = nil
            hasAPIKey = true
        } else {
            apiKeyError = String(localized: "Не получилось сохранить ключ в Keychain. Разблокируйте телефон и попробуйте ещё раз.")
            HapticManager.shared.trigger(.error)
        }
    }

    /// Поле CSV: значения с запятой, кавычкой или переводом строки берутся в кавычки
    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func exportDataToClipboard() {
        var csvText = "Date,Type,Category,Title,Amount\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        for t in financeService.transactions {
            let dateStr = formatter.string(from: t.date)
            let fields = [dateStr, t.type.rawValue, t.category.displayName, t.title, String(t.amount)]
            csvText += fields.map(Self.csvField).joined(separator: ",") + "\n"
        }
        
        UIPasteboard.general.string = csvText
        withAnimation {
            exportMessage = String(localized: "Скопировано")
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
