import SwiftUI

/// Что делаем с деньгами копилки
enum GoalMoveMode: String, Identifiable {
    case deposit
    case withdraw

    var id: String { rawValue }
}

/// Пополнение и снятие: сумма, быстрые варианты, заметка. Когда цель достигнута, лист показывает поздравление.
@MainActor
struct GoalMoneySheet: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    let goalID: UUID
    let mode: GoalMoveMode

    private enum Field: Hashable {
        case amount, note
    }

    @State private var amountText = ""
    @State private var note = ""
    @State private var showsError = false
    @State private var isCelebrating = false
    @FocusState private var focusedField: Field?

    private var goal: Goal? { financeService.goals.first { $0.id == goalID } }

    private var parsedAmount: Double? {
        guard let value = GoalQuickAmounts.parse(amountText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        Group {
            if let goal {
                if isCelebrating {
                    celebration(goal)
                } else {
                    form(goal)
                }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .monoScreen()
    }

    // MARK: - Ввод суммы
    private func form(_ goal: Goal) -> some View {
        let plan = GoalPlan(goal: goal)
        return ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text(mode == .deposit ? String(localized: "Пополнение") : String(localized: "Снятие"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                    Text(goal.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.top, 24)

                ZStack(alignment: .trailing) {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(Theme.number(44, weight: .bold))
                        .foregroundColor(.white)
                        .focused($focusedField, equals: .amount)
                        .padding(.horizontal, 44)
                    Text(CurrencyManager.shared.baseCurrency.symbol)
                        .font(Theme.number(26, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.trailing, 8)
                }

                quickAmounts(plan)

                TextField(String(localized: "Заметка (необязательно)"), text: $note)
                    .focused($focusedField, equals: .note)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .monoSurface(cornerRadius: 16)

                outcomeLine(goal)

                PrimaryButton(title: mode == .deposit ? String(localized: "Пополнить") : String(localized: "Снять")) {
                    submit(goal)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: amountText) { _, _ in
            showsError = false
        }
        .task {
            // Клавиатура поднимается после появления листа: иначе фокус в поле нередко теряется
            guard !ScreenshotMode.isTour else { return }
            try? await Task.sleep(for: .milliseconds(350))
            focusedField = .amount
        }
        #if DEBUG
        .task {
            await playTour(goal)
        }
        #endif
    }

    /// Доли цели и «всё сразу»: остаток до цели при пополнении, вся сумма при снятии
    private func quickAmounts(_ plan: GoalPlan) -> some View {
        let shares = mode == .deposit
            ? GoalQuickAmounts.deposit(target: plan.target, remaining: plan.remaining)
            : GoalQuickAmounts.withdraw(current: plan.saved)
        let full = mode == .deposit ? plan.remaining : plan.saved
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shares, id: \.self) { value in
                    chip(title: CurrencyManager.shared.baseCurrency.symbol + " " + GoalQuickAmounts.grouped(value), value: value)
                }
                if full > 0 {
                    chip(title: mode == .deposit ? String(localized: "Остаток") : String(localized: "Всё"), value: full)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(title: String, value: Double) -> some View {
        Button {
            HapticManager.shared.selection()
            amountText = GoalQuickAmounts.plain(value)
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Theme.surfaceRaised)
                .clipShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    /// Что получится после операции, либо что не так с суммой
    @ViewBuilder
    private func outcomeLine(_ goal: Goal) -> some View {
        if showsError {
            Text(errorText(goal))
                .font(.system(size: 13))
                .foregroundColor(Color.red)
                .multilineTextAlignment(.center)
        } else if let amount = parsedAmount {
            let after = max(goal.currentAmount + (mode == .deposit ? amount : -amount), 0)
            Text(String(localized: "Станет: \(GoalText.money(after)) из \(GoalText.money(goal.targetAmount))"))
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func errorText(_ goal: Goal) -> String {
        if mode == .withdraw, let amount = parsedAmount, amount > goal.currentAmount {
            return String(localized: "В копилке только \(GoalText.money(goal.currentAmount))")
        }
        return String(localized: "Введите сумму больше нуля")
    }

    #if DEBUG
    /// Ролик App Store: остаток до цели набирается по цифре, затем пополнение отправляется и появляется поздравление
    private func playTour(_ goal: Goal) async {
        guard ScreenshotMode.isTour else { return }
        try? await Task.sleep(for: .milliseconds(800))
        for character in GoalQuickAmounts.plain(GoalPlan(goal: goal).remaining) {
            amountText.append(character)
            try? await Task.sleep(for: .milliseconds(140))
        }
        try? await Task.sleep(for: .milliseconds(800))
        submit(goal)
    }
    #endif

    private func submit(_ goal: Goal) {
        guard let amount = parsedAmount else {
            showsError = true
            HapticManager.shared.trigger(.error)
            return
        }
        let outcome = mode == .deposit
            ? financeService.deposit(goalID: goal.id, amount: amount, note: note)
            : financeService.withdraw(goalID: goal.id, amount: amount, note: note)
        switch outcome {
        case .rejected:
            showsError = true
            HapticManager.shared.trigger(.error)
        case .done:
            HapticManager.shared.trigger(.success)
            dismiss()
        case .reachedTarget:
            HapticManager.shared.trigger(.success)
            focusedField = nil
            withAnimation(Motion.spring) {
                isCelebrating = true
            }
        }
    }

    // MARK: - Цель достигнута
    private func celebration(_ goal: Goal) -> some View {
        ZStack {
            ConfettiView()

            VStack(spacing: 14) {
                Spacer()
                GoalIconBadge(goal: goal, size: 88)
                Text(String(localized: "Цель достигнута!"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(goal.title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Text(GoalText.money(goal.currentAmount))
                    .font(Theme.number(34, weight: .bold))
                    .foregroundColor(Theme.accent)
                Spacer()
                PrimaryButton(title: String(localized: "Отлично")) {
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

/// Салют из конфетти: куски разлетаются от центра вниз и гаснут; при «Уменьшении движения» не показывается
struct ConfettiView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBursting = false
    @State private var pieces = ConfettiPiece.make(count: 40)

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(piece.color)
                        .frame(width: piece.size, height: piece.size * 0.5)
                        .rotationEffect(.degrees(isBursting ? piece.spin : 0))
                        .offset(x: isBursting ? piece.dx : 0, y: isBursting ? piece.dy : -40)
                        .opacity(isBursting ? 0 : 1)
                        .animation(.easeOut(duration: piece.duration), value: isBursting)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            isBursting = true
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGFloat
    let dx: CGFloat
    let dy: CGFloat
    let spin: Double
    let duration: Double

    private static let colors: [Color] = [
        Theme.accent, Color.white, Color.orange, Color.pink, Color.cyan, Color.yellow
    ]

    static func make(count: Int) -> [ConfettiPiece] {
        (0..<count).map { _ in
            ConfettiPiece(
                color: colors.randomElement() ?? Theme.accent,
                size: CGFloat.random(in: 8...16),
                dx: CGFloat.random(in: -170...170),
                dy: CGFloat.random(in: -120...300),
                spin: Double.random(in: -540...540),
                duration: Double.random(in: 1.2...2.2)
            )
        }
    }
}
