import SwiftUI

/// Cards management view.
/// Adaptive for all iPhone screen sizes.
struct CardsView: View {
        let financeService: FinanceService

        private var isSmallScreen: Bool {
                    UIScreen.main.bounds.height < 750
        }

        var body: some View {
                    NavigationStack {
                                    ScrollView {
                                                        VStack(spacing: isSmallScreen ? 16 : 24) {
                                                                                ForEach(financeService.cards) { card in
                                                                                                                                       CardItemView(card: card, financeService: financeService)
                                                                                                              }
                                                        }
                                                        .padding(.horizontal)
                                                        .padding(.top, 16)
                                                        .padding(.bottom, isSmallScreen ? 90 : 110) // Offset for tab bar
                                    }
                                    .background(Color(hex: "#0E0F12")) // Dark background
                                    .preferredColorScheme(.dark)
                                    .navigationBarTitleDisplayMode(.inline)
                                    .toolbar {
                                                        ToolbarItem(placement: .topBarLeading) {
                                                                                Text("Cards")
                                                                                    .font(.system(size: isSmallScreen ? 28 : 32, weight: .bold))
                                                                                    .foregroundColor(.white)
                                                        }
                                                        ToolbarItem(placement: .topBarTrailing) {
                                                                                Button {
                                                                                                            HapticManager.shared.trigger(.success)
                                                                                } label: {
                                                                                                            Text("Order a card")
                                                                                                                .font(.system(size: isSmallScreen ? 11 : 13, weight: .semibold))
                                                                                                                .foregroundColor(.black)
                                                                                                                .padding(.horizontal, isSmallScreen ? 12 : 16)
                                                                                                                .padding(.vertical, isSmallScreen ? 6 : 8)
                                                                                                                .background(Color.white)
                                                                                                                .clipShape(Capsule())
                                                                                }
                                                        }
                                    }
                    }
        }
}

/// Card item view.
struct CardItemView: View {
        let card: Card
        let financeService: FinanceService

        private var isSmallScreen: Bool {
                    UIScreen.main.bounds.height < 750
        }

        var body: some View {
                    VStack(alignment: .leading, spacing: 0) {
                                    // Top part (Type and card number)
                                    HStack {
                                                        Text(card.type)
                                                            .font(.system(size: isSmallScreen ? 14 : 16, weight: .medium))
                                                            .foregroundColor(.white.opacity(0.85))
                                                        Spacer()
                                                        Text("**** \(card.number)")
                                                            .font(.system(size: isSmallScreen ? 14 : 16, weight: .semibold, design: .monospaced))
                                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.top, isSmallScreen ? 18 : 24)

                                    Spacer()

                                    // Bottom part
                                    HStack(alignment: .bottom) {
                                                        HStack(spacing: 10) {
                                                                                // Freeze button
                                                                                CardActionButton(iconName: card.isFrozen ? "snowflake.circle.fill" : "snowflake") {
                                                                                                            HapticManager.shared.trigger(.success)
                                                                                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                                                                                                                            financeService.toggleFreezeCard(id: card.id)
                                                                                                            }
                                                                                }
                                                                                .foregroundColor(card.isFrozen ? .blue : .white)

                                                                                // Details button
                                                                                CardActionButton(iconName: "creditcard") {
                                                                                                            HapticManager.shared.impact(.light)
                                                                                }

                                                                                // Settings button
                                                                                CardActionButton(iconName: "gearshape") {
                                                                                                            HapticManager.shared.impact(.light)
                                                                                }
                                                        }
                                                        Spacer()
                                                        // MasterCard logo
                                                        MasterCardLogoView()
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, isSmallScreen ? 18 : 24)
                    }
                    .frame(height: isSmallScreen ? 150 : 180) // Adaptive card height
                    .background {
                                    RoundedRectangle(cornerRadius: isSmallScreen ? 20 : 24)
                                        .fill(
                                                                LinearGradient(
                                                                                            colors: card.gradientColors.map { Color(hex: $0) },
                                                                                            startPoint: .topLeading,
                                                                                            endPoint: .bottomTrailing
                                                                )
                                        )
                                        .opacity(card.isFrozen ? 0.55 : 1.0)
                    }
                    .overlay {
                                    if card.isFrozen {
                                                        RoundedRectangle(cornerRadius: isSmallScreen ? 20 : 24)
                                                            .stroke(Color.blue.opacity(0.35), lineWidth: 2)
                                    }
                    }
                    // Neon glow
                    .shadow(color: Color(hex: card.colorHex).opacity(card.isFrozen ? 0.12 : 0.38), radius: isSmallScreen ? 12 : 18, x: 0, y: isSmallScreen ? 6 : 10)
        }
}


/// Translucent action button
struct CardActionButton: View {
        let iconName: String
        let action: () -> Void

        var body: some View {
                    Button(action: action) {
                                    Image(systemName: iconName)
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                        .frame(width: 36, height: 36)
                                        .background(Color.white.opacity(0.12))
                                        .clipShape(Circle())
                                        .overlay {
                                                                Circle()
                                                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        }
                    }
        }
}

/// MasterCard logo mockup
struct MasterCardLogoView: View {
        var body: some View {
                    HStack(spacing: -10) {
                                    Circle()
                                        .fill(Color.white.opacity(0.22))
                                        .frame(width: 28, height: 28)
                                    Circle()
                                        .fill(Color.white.opacity(0.14))
                                        .frame(width: 28, height: 28)
                    }
        }
}
                                                    
