import SwiftUI
import UIKit

/// Раздел настроек «Напоминания»: что напоминать и во сколько
struct ReminderSettingsSection: View {
    let financeService: FinanceService
    @AppStorage(ReminderKeys.debts) private var debts = true
    @AppStorage(ReminderKeys.goalDeadlines) private var goalDeadlines = true
    @AppStorage(ReminderKeys.goalSaving) private var goalSavingRaw = GoalSavingReminder.off.rawValue
    @AppStorage(ReminderKeys.cardExpiry) private var cardExpiry = true
    @AppStorage(ReminderKeys.dailyLog) private var dailyLog = false
    @AppStorage(ReminderKeys.time) private var minutes = 600
    @AppStorage(ReminderKeys.dailyLogTime) private var dailyLogMinutes = 1260
    @State private var isDenied = false

    /// Текущие настройки целиком: по их изменению напоминания пересоздаются
    private var current: ReminderSettings {
        ReminderSettings(
            debts: debts,
            goalDeadlines: goalDeadlines,
            goalSaving: GoalSavingReminder(rawValue: goalSavingRaw) ?? .off,
            cardExpiry: cardExpiry,
            dailyLog: dailyLog,
            minutes: minutes,
            dailyLogMinutes: dailyLogMinutes
        )
    }

    var body: some View {
        Section {
            if isDenied {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Label("Уведомления выключены в настройках iOS", systemImage: "bell.slash")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundColor(.secondary)
                    }
                }
            }

            NavigationLink {
                CustomRemindersView(financeService: financeService)
            } label: {
                HStack {
                    Label("Мои напоминания", systemImage: "bell.badge")
                    Spacer()
                    if !financeService.customReminders.isEmpty {
                        Text("\(financeService.customReminders.count)")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Toggle(isOn: $debts) {
                Label("Долги и кредиты", systemImage: "person.2")
            }
            Toggle(isOn: $goalDeadlines) {
                Label("Сроки копилок", systemImage: "flag")
            }
            Picker(selection: $goalSavingRaw) {
                ForEach(GoalSavingReminder.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            } label: {
                Label("Отложить в копилки", systemImage: "banknote")
            }
            Toggle(isOn: $cardExpiry) {
                Label("Срок действия карт", systemImage: "creditcard")
            }
            DatePicker(selection: time($minutes), displayedComponents: .hourAndMinute) {
                Label("Во сколько напоминать", systemImage: "clock")
            }
            Toggle(isOn: $dailyLog) {
                Label("Вечером: записать траты", systemImage: "square.and.pencil")
            }
            if dailyLog {
                DatePicker(selection: time($dailyLogMinutes), displayedComponents: .hourAndMinute) {
                    Label("Время вечернего напоминания", systemImage: "moon")
                }
            }
        } header: {
            Text("Напоминания")
        } footer: {
            Text("О долге напомним заранее (срок выбирается у каждого долга), в день срока, на следующий день и через неделю, пока долг не отмечен погашенным. В уведомлении о долге есть кнопки «Погашен» и «Напомнить завтра».")
        }
        .task {
            isDenied = await ReminderService.isAuthorizationDenied()
        }
        .onChange(of: current) { old, new in
            ReminderService.shared.update(from: financeService)
            if new.enabledCount > old.enabledCount {
                Task {
                    _ = await PurchasePromptService.shared.requestAuthorization()
                    isDenied = await ReminderService.isAuthorizationDenied()
                }
            }
        }
    }

    /// Время в минутах от полуночи как дата для выбора часов и минут
    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }
}

private extension ReminderSettings {
    /// Сколько видов напоминаний включено: если стало больше, приложение просит разрешение на уведомления
    var enabledCount: Int {
        [debts, goalDeadlines, goalSaving != .off, cardExpiry, dailyLog].filter { $0 }.count
    }
}
