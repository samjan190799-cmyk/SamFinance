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
    @State private var aiConsent = AIProvider.selected.hasConsent

    var body: some View {
        NavigationStack {
            List {
                // Секция профиля
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(Theme.accent)
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
                            .labelStyle(.settingsIcon(.sky))
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
                            .labelStyle(.settingsIcon(.mint))
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
                                .labelStyle(.settingsIcon(.aqua))
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
                                .labelStyle(.settingsIcon(.peach))
                            Spacer()
                            Text(exportMessage ?? "CSV")
                                .foregroundColor(exportMessage != nil ? .green : .secondary)
                        }
                    }
                } header: {
                    Text("preferences".localized)
                }
                
                // Облачный ИИ: ключ задан сборкой, здесь только согласие на отправку данных
                if AIKeyStore.key(for: AIProvider.selected) != nil {
                    aiSection
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
                                .labelStyle(.settingsIcon(.sun))
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
                                .labelStyle(.settingsIcon(.rose))
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
                            .labelStyle(.settingsIcon(.slate))
                    }
                    HStack {
                        Label(String(localized: "Версия"), systemImage: "info.circle")
                            .labelStyle(.settingsIcon(.sand))
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
                            .labelStyle(.settingsIcon(.coral))
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

    // MARK: - ИИ-помощник
    /// Ключ, сервис и модель задаёт сборка (AIConfig), поэтому здесь только согласие на отправку данных: его можно отозвать
    private var aiSection: some View {
        Section {
            Toggle(isOn: $aiConsent) {
                Label("Отправлять данные ИИ", systemImage: "sparkles")
                    .labelStyle(.settingsIcon(.lilac))
            }
            .onAppear {
                // Согласие могли дать или отозвать в чате, пока этот экран был закрыт
                aiConsent = AIProvider.selected.hasConsent
            }
            .onChange(of: aiConsent) { _, granted in
                AIProvider.selected.setConsent(granted)
                HapticManager.shared.selection()
            }
        } header: {
            Text("ИИ-помощник")
        } footer: {
            Text("Ответы на любые вопросы и разбор чеков, выписок и скриншотов идут через \(AIProvider.selected.company). Если включено, вопрос, скриншоты и сводка ваших операций, карт (последние 4 цифры), долгов, копилок и напоминаний отправляются туда. Банковские СМС распознаются на телефоне и в облако не уходят. Если выключить, приложение спросит разрешение снова перед следующей отправкой.")
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
        // Переписка с ИИ — часть данных приложения: в ней суммы и названия из операций
        AIChatStore.shared.reset()
        HapticManager.shared.trigger(.success)
    }
}
