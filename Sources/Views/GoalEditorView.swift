import SwiftUI

/// Запрос на открытие редактора копилки: новая (при желании с идеей или картой) или правка существующей
struct GoalEditorRequest: Identifiable {
    let id = UUID()
    var editing: Goal? = nil
    var idea: GoalIdea? = nil
    var card: Card? = nil
}

/// Создание и правка копилки: название, цель, срок, карта, цвет и значок с предпросмотром на лету
@MainActor
struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    /// Копилка, которую правят; nil — создаётся новая
    let editing: Goal?

    private enum Field: Hashable {
        case title, target, initial
    }

    @State private var title: String
    @State private var targetText: String
    @State private var initialText = ""
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var cardID: UUID?
    @State private var gradient: [String]
    @State private var symbol: String?
    @State private var showsErrors = false
    @State private var isConfirmingDelete = false
    @FocusState private var focusedField: Field?

    init(financeService: FinanceService, request: GoalEditorRequest) {
        self.financeService = financeService
        let goal = request.editing
        self.editing = goal
        let colors = goal?.gradientColors ?? request.idea?.colors ?? []
        let startGradient: [String]
        if colors.count >= 2 {
            startGradient = colors
        } else if let single = colors.first {
            startGradient = [single, single]
        } else {
            startGradient = CardPreset.all[0].colors
        }
        _title = State(initialValue: goal?.title ?? request.idea?.title ?? "")
        _targetText = State(initialValue: goal.map { GoalQuickAmounts.plain($0.targetAmount) } ?? "")
        _hasDeadline = State(initialValue: goal?.deadline != nil)
        _deadline = State(initialValue: goal?.deadline ?? Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date())
        _cardID = State(initialValue: goal?.cardId ?? request.card?.id)
        _gradient = State(initialValue: startGradient)
        _symbol = State(initialValue: goal?.symbol ?? request.idea?.symbol)
    }

    // MARK: - Значения полей

    private var isEditing: Bool { editing != nil }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var parsedTarget: Double? {
        guard let value = GoalQuickAmounts.parse(targetText), value > 0 else { return nil }
        return value
    }

    /// Уже накопленная сумма при создании; пустое поле означает ноль
    private var parsedInitial: Double? {
        let trimmed = initialText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        guard let value = GoalQuickAmounts.parse(trimmed), value >= 0 else { return nil }
        return value
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Проверки

    private var titleError: String? {
        trimmed(title).isEmpty ? String(localized: "Назовите копилку") : nil
    }

    private var targetError: String? {
        parsedTarget == nil ? String(localized: "Введите сумму цели больше нуля") : nil
    }

    private var initialError: String? {
        parsedInitial == nil ? String(localized: "Введите сумму числом") : nil
    }

    private var deadlineError: String? {
        hasDeadline && deadline < today ? String(localized: "Выберите сегодняшний или будущий день") : nil
    }

    private var isValid: Bool {
        titleError == nil && targetError == nil && deadlineError == nil && (isEditing || initialError == nil)
    }

    /// Как будет выглядеть копилка в списке
    private var previewGoal: Goal {
        var goal = Goal(
            id: editing?.id ?? UUID(),
            cardId: cardID,
            title: trimmed(title).isEmpty ? String(localized: "Новая копилка") : trimmed(title),
            targetAmount: parsedTarget ?? 0,
            currentAmount: editing?.currentAmount ?? (parsedInitial ?? 0),
            colorHex: gradient[0],
            gradientColors: gradient,
            deadline: hasDeadline ? deadline : nil,
            symbol: symbol,
            createdAt: editing?.createdAt ?? Date(),
            completedAt: editing?.completedAt,
            entries: editing?.entries ?? []
        )
        if goal.targetAmount <= 0 {
            goal.targetAmount = 1
            goal.currentAmount = 0
        }
        return goal
    }

    // MARK: - Экран

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    GoalCardView(goal: previewGoal)
                        .animation(Motion.spring, value: gradient)
                        .animation(Motion.spring, value: symbol)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if !isEditing {
                    ideasSection
                }

                basicsSection
                deadlineSection
                cardSection

                Section {
                    PresetSwatchRow(gradient: $gradient)
                } header: {
                    Text("card_color_theme".localized)
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(GoalSymbol.all, id: \.self) { name in
                                symbolButton(name)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text(String(localized: "Значок"))
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            HapticManager.shared.trigger(.warning)
                            isConfirmingDelete = true
                        } label: {
                            Text(String(localized: "Удалить копилку"))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .monoForm()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? String(localized: "Правка копилки") : String(localized: "Новая копилка"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save".localized) {
                        save()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(String(localized: "Готово")) {
                        focusedField = nil
                    }
                }
            }
            .confirmationDialog(
                String(localized: "Удалить копилку?"),
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Удалить копилку"), role: .destructive) {
                    deleteGoal()
                }
                Button("cancel".localized, role: .cancel) {}
            } message: {
                Text(String(localized: "Деньги останутся на карте: копилка просто перестанет их откладывать."))
            }
        }
    }

    // MARK: - Разделы

    private var ideasSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GoalIdea.all) { idea in
                        ideaChip(idea)
                    }
                }
            }
        } header: {
            Text(String(localized: "Идеи"))
        }
    }

    private func ideaChip(_ idea: GoalIdea) -> some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(Motion.spring) {
                title = idea.title
                symbol = idea.symbol
                gradient = idea.colors
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: idea.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(idea.title)
                    .font(.system(size: 13))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var basicsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                TextField(String(localized: "Название"), text: $title)
                    .focused($focusedField, equals: .title)
                notes(error: showsErrors ? titleError : nil)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "Цель (\(CurrencyManager.shared.baseCurrency.symbol))"))
                    Spacer()
                    TextField("0", text: $targetText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .target)
                }
                notes(error: showsErrors ? targetError : nil)
            }

            if !isEditing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "Уже накоплено (\(CurrencyManager.shared.baseCurrency.symbol))"))
                        Spacer()
                        TextField("0", text: $initialText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .initial)
                    }
                    notes(error: showsErrors ? initialError : nil)
                }
            }
        } header: {
            Text(String(localized: "Копилка"))
        } footer: {
            if isEditing {
                Text(String(localized: "Накопленную сумму меняют кнопками «Пополнить» и «Снять» на экране копилки."))
            }
        }
    }

    private var deadlineSection: some View {
        Section {
            Toggle(String(localized: "Срок"), isOn: $hasDeadline.animation(Motion.spring))
                .tint(Theme.accent)

            if hasDeadline {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        deadlineChip(title: String(localized: "3 месяца"), months: 3)
                        deadlineChip(title: String(localized: "6 месяцев"), months: 6)
                        deadlineChip(title: String(localized: "1 год"), months: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    DatePicker(
                        String(localized: "Накопить к"),
                        selection: $deadline,
                        in: today...,
                        displayedComponents: .date
                    )
                    notes(error: showsErrors ? deadlineError : nil)
                }
            }
        } header: {
            Text(String(localized: "Срок"))
        } footer: {
            Text(String(localized: "С указанным сроком приложение подскажет, сколько откладывать в неделю или месяц."))
        }
    }

    private func deadlineChip(title: String, months: Int) -> some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(Motion.spring) {
                deadline = Calendar.current.date(byAdding: .month, value: months, to: Date()) ?? deadline
            }
        } label: {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var cardSection: some View {
        Section {
            Picker(String(localized: "Карта"), selection: $cardID) {
                Text(String(localized: "Без карты")).tag(UUID?.none)
                ForEach(financeService.cards) { card in
                    Text("\(card.type) •••• \(card.last4)").tag(Optional(card.id))
                }
            }
            .pickerStyle(.menu)
        } footer: {
            Text(String(localized: "Деньги остаются на карте, приложение лишь откладывает их под цель. На карте будет видно, сколько осталось свободно."))
        }
    }

    private func symbolButton(_ name: String) -> some View {
        let isSelected = symbol == name
        return Button {
            HapticManager.shared.selection()
            withAnimation(Motion.spring) {
                symbol = name
            }
        } label: {
            Image(systemName: name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isSelected ? Theme.onAccent : .white)
                .frame(width: 44, height: 44)
                .background(isSelected ? Theme.accent : Theme.surfaceRaised)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(GoalSymbol.title(name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func notes(error: String?) -> some View {
        if let error {
            Text(error)
                .font(.footnote)
                .foregroundColor(Color.red)
        }
    }

    // MARK: - Действия

    private func save() {
        guard isValid, let target = parsedTarget else {
            showsErrors = true
            HapticManager.shared.trigger(.error)
            return
        }
        let colors = gradient
        let endDay = hasDeadline ? Calendar.current.startOfDay(for: deadline) : nil

        if var goal = editing {
            goal.title = trimmed(title)
            goal.targetAmount = target
            goal.deadline = endDay
            goal.symbol = symbol
            goal.colorHex = colors[0]
            goal.gradientColors = colors
            goal.cardId = cardID
            financeService.updateGoal(goal)
        } else {
            let goal = Goal(
                cardId: cardID,
                title: trimmed(title),
                targetAmount: target,
                currentAmount: parsedInitial ?? 0,
                colorHex: colors[0],
                gradientColors: colors,
                deadline: endDay,
                symbol: symbol
            )
            financeService.addGoal(goal)
        }
        if endDay != nil {
            Task {
                // Разрешение нужно для напоминаний о сроке копилки
                _ = await PurchasePromptService.shared.requestAuthorization()
            }
        }
        HapticManager.shared.trigger(.success)
        dismiss()
    }

    private func deleteGoal() {
        guard let goal = editing else { return }
        financeService.deleteGoal(id: goal.id)
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
