import SwiftUI

/// Свои напоминания: список с ближайшим сроком, добавление, правка и удаление смахиванием
struct CustomRemindersView: View {
    let financeService: FinanceService
    @State private var isShowingAdd = false
    @State private var editing: CustomReminder? = nil

    /// Ближайшие впереди, прошедшие разовые в конце
    private var sorted: [CustomReminder] {
        let now = Date()
        let calendar = Calendar.current
        return financeService.customReminders.sorted { lhs, rhs in
            let first = ReminderPlanner.occurrences(of: lhs, now: now, calendar: calendar).first
            let second = ReminderPlanner.occurrences(of: rhs, now: now, calendar: calendar).first
            switch (first, second) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.date > rhs.date
            }
        }
    }

    var body: some View {
        List {
            if financeService.customReminders.isEmpty {
                Section {
                    Text("Своих напоминаний пока нет. Нажмите «+» или попросите ИИ в чате: «напомни 5 ноября оплатить интернет».")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            } else {
                Section {
                    ForEach(sorted) { reminder in
                        Button {
                            editing = reminder
                        } label: {
                            row(reminder)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                HapticManager.shared.trigger(.warning)
                                financeService.deleteCustomReminder(id: reminder.id)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .monoForm()
        .navigationTitle("Мои напоминания")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    HapticManager.shared.impact(.light)
                    isShowingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Новое напоминание"))
            }
        }
        .sheet(isPresented: $isShowingAdd) {
            CustomReminderEditor(financeService: financeService, reminder: nil)
        }
        .sheet(item: $editing) { reminder in
            CustomReminderEditor(financeService: financeService, reminder: reminder)
        }
    }

    private func row(_ reminder: CustomReminder) -> some View {
        let next = ReminderPlanner.occurrences(of: reminder, now: Date(), calendar: .current).first
        let isPast = next == nil
        var details = (next ?? reminder.date).formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
        if reminder.repeatRule != .never {
            details += " · " + reminder.repeatRule.title
        } else if isPast {
            details += " · " + String(localized: "прошло")
        }
        return VStack(alignment: .leading, spacing: 3) {
            Text(reminder.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isPast ? .secondary : .white)
                .lineLimit(2)
            Text(details)
                .font(.system(size: 13))
                .foregroundColor(isPast ? .secondary : Theme.accent)
            if let note = reminder.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Форма нового или изменяемого напоминания
struct CustomReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    let reminder: CustomReminder?

    @State private var title: String
    @State private var date: Date
    @State private var repeatRule: ReminderRepeat
    @State private var note: String

    init(financeService: FinanceService, reminder: CustomReminder?) {
        self.financeService = financeService
        self.reminder = reminder
        _title = State(initialValue: reminder?.title ?? "")
        _date = State(initialValue: reminder?.date ?? Self.defaultDate())
        _repeatRule = State(initialValue: reminder?.repeatRule ?? .never)
        _note = State(initialValue: reminder?.note ?? "")
    }

    /// Завтра в 10:00
    private static func defaultDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        return ReminderPlanner.moment(tomorrow, minutes: 600, calendar: calendar) ?? tomorrow
    }

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Что напомнить", text: $title)
                        .textInputAutocapitalization(.sentences)
                    DatePicker("Когда", selection: $date)
                    Picker("Повтор", selection: $repeatRule) {
                        ForEach(ReminderRepeat.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    TextField("Заметка (необязательно)", text: $note)
                } footer: {
                    if repeatRule == .never && date <= Date() {
                        Text("Это время уже прошло: напоминание не придёт.")
                    }
                }
            }
            .monoForm()
            .navigationTitle(reminder == nil ? String(localized: "Новое напоминание") : String(localized: "Напоминание"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        save()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
    }

    private func save() {
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = CustomReminder(
            id: reminder?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            repeatRule: repeatRule,
            note: cleanedNote.isEmpty ? nil : cleanedNote
        )
        if reminder == nil {
            financeService.addCustomReminder(saved)
        } else {
            financeService.updateCustomReminder(saved)
        }
        Task {
            // Разрешение нужно, чтобы напоминание появилось
            _ = await PurchasePromptService.shared.requestAuthorization()
        }
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
