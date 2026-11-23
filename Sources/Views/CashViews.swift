import SwiftUI

/// Что показано на экране «Карты»: карусель карт или наличные
enum CardsSection: Hashable, CaseIterable {
    case cards
    case cash
}

/// Плитка наличных на экране «Карты»: деньги на руках, без номера и срока, как у карты
@MainActor
struct CashTile: View {
    let balance: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 22, weight: .semibold))
                Text(String(localized: "Наличные"))
                    .font(.system(size: 18, weight: .semibold))
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            Text(String(localized: "Баланс"))
                .font(.system(size: 13, weight: .medium))
                .opacity(0.7)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(CurrencyManager.shared.formatNumber(balance))
                    .font(Theme.number(44, weight: .bold))
                    .tracking(-1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: balance))
                    .animation(Motion.digits, value: balance)
                Text(CurrencyManager.shared.currentCurrency.symbol)
                    .font(Theme.number(22, weight: .bold))
            }
            .padding(.top, 4)
        }
        .foregroundColor(Theme.onAccent)
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .background(
            LinearGradient(
                colors: [PaletteColor.mint.color, PaletteColor.aqua.color],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}

/// Ряд кнопок ручной правки баланса: пополнить, убавить, обнулить. «Обнулить» без денег недоступно.
@MainActor
struct BalanceActionRow: View {
    let isEmpty: Bool
    let onTopUp: () -> Void
    let onReduce: () -> Void
    let onZero: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            actionButton(String(localized: "Пополнить"), action: onTopUp)
            actionButton(String(localized: "Убавить"), action: onReduce)
            actionButton(String(localized: "Обнулить"), action: onZero)
                .disabled(isEmpty)
                .opacity(isEmpty ? 0.4 : 1)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.impact(.light)
            action()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.surfaceRaised)
                .clipShape(Capsule())
        }
        .buttonStyle(.pressable)
    }
}
