import SwiftUI

/// Настройки по видам записей: у кредитов, долгов людям, разовых платежей и каждого вида регулярных платежей
/// свои напоминания, время и повтор. Открывается из настроек напоминаний и с экрана долгов.
struct DebtTypeSettingsView: View {
    let financeService: FinanceService
    /// В окне с экрана долгов нужна кнопка «Готово»; в настройках её заменяет «Назад»
    var showsDoneButton = false

    @Environment(\.dismiss) private var dismiss
    @State private var settings = DebtTypeSettings.load()

    var body: some View {
        Form {
            Section {
                ForEach(DebtProfile.debts) { profile in
                    link(to: profile)
                }
            } header: {
                Text("Долги и кредиты")
            }

            Section {
                ForEach(DebtProfile.payments) { profile in
                    link(to: profile)
                }
            } header: {
                Text("Платежи")
            } footer: {
                Text("Напоминания, время и повтор можно настроить для каждого вида отдельно. Настройки подставляются в новые записи и действуют на записи, у которых нет своего напоминания.")
            }
        }
        .monoForm()
        .navigationTitle("Настройки по видам")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: settings) { _, newValue in
            newValue.save()
            ReminderService.shared.update(from: financeService)
        }
    }

    private func link(to profile: DebtProfile) -> some View {
        NavigationLink {
            DebtTypeSettingDetail(profile: profile, settings: $settings, cards: financeService.cards)
        } label: {
            HStack {
                Label(profile.title, systemImage: profile.icon)
                Spacer()
                Text(summary(of: profile))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }

    /// «За день · 09:00», у выключенного вида — «Выкл.»
    private func summary(of profile: DebtProfile) -> String {
        let setting = settings[profile]
        guard setting.isEnabled else { return String(localized: "Выкл.") }
        var text = setting.reminder.title
        if let minutes = setting.minutes {
            text += " · " + String(format: "%02ld:%02ld", minutes / 60, minutes % 60)
        }
        return text
    }
}

/// Настройки одного вида записей
struct DebtTypeSettingDetail: View {
    let profile: DebtProfile
    @Binding var settings: DebtTypeSettings
    /// Карты приложения: из них выбирается карта оплаты по умолчанию
    var cards: [Card] = []

    private var setting: Binding<DebtTypeSetting> {
        Binding(
            get: { settings[profile] },
            set: { settings[profile] = $0 }
        )
    }

    /// «Своё время» включено, когда у вида есть время; общее время хранится в настройках напоминаний
    private var hasCustomTime: Binding<Bool> {
        Binding(
            get: { setting.wrappedValue.minutes != nil },
            set: { isOn in
                setting.wrappedValue.minutes = isOn ? (setting.wrappedValue.minutes ?? ReminderSettings.load().minutes) : nil
            }
        )
    }

    /// Время напоминаний как дата для выбора часов и минут
    private var time: Binding<Date> {
        Binding(
            get: {
                let minutes = setting.wrappedValue.minutes ?? 600
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                setting.wrappedValue.minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    /// Карта оплаты вида; удалённая карта показывается как «Не записывать»
    private var cardBinding: Binding<UUID?> {
        Binding(
            get: { setting.wrappedValue.cardId.flatMap { id in cards.contains { $0.id == id } ? id : nil } },
            set: { setting.wrappedValue.cardId = $0 }
        )
    }

    /// Напоминание «заранее» без варианта «не напоминать»: его заменяет выключатель вида
    private var reminderOptions: [DebtReminder] {
        DebtReminder.allCases.filter { $0 != .off }
    }

    private var repeatOptions: [ReminderRepeat] {
        ReminderRepeat.allCases.filter { $0 != .never }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Напоминать", isOn: setting.isEnabled)
            } footer: {
                Text("Если выключить, по записям этого вида напоминаний не будет совсем.")
            }

            if setting.wrappedValue.isEnabled {
                Section {
                    Picker("Заранее", selection: setting.reminder) {
                        ForEach(reminderOptions) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Picker("После срока", selection: setting.late) {
                        ForEach(LateReminders.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Toggle("Своё время", isOn: hasCustomTime)
                    if setting.wrappedValue.minutes != nil {
                        DatePicker("Время", selection: time, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Когда напоминать")
                } footer: {
                    Text("Без своего времени напоминания приходят в общее время из настроек напоминаний. В день срока напоминание приходит всегда.")
                }
            }

            if !cards.isEmpty {
                PaymentCardSection(cards: cards, isIncome: profile == .owedToMe, cardID: cardBinding)
            }

            if profile.isRecurringBill {
                Section {
                    Picker("Повтор", selection: setting.repeatRule) {
                        ForEach(repeatOptions) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Stepper(value: setting.repeatInterval, in: 1...36) {
                        Text(setting.wrappedValue.repeatRule.title(every: setting.wrappedValue.repeatInterval))
                    }
                    Toggle("Сумма меняется", isOn: setting.isVariableAmount)
                } header: {
                    Text("Новые платежи")
                } footer: {
                    Text("Так заполняется форма нового платежа этого вида. Если сумма меняется, при оплате приложение спросит, сколько вышло.")
                }
            }

            Section {
                Button("Вернуть стандартные", role: .destructive) {
                    HapticManager.shared.selection()
                    settings.reset(profile)
                }
                .disabled(!settings.isCustomized(profile))
            }
        }
        .monoForm()
        .navigationTitle(profile.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
