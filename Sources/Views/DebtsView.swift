import SwiftUI

/// Экран управления долгами с вкладками «Кредиты» и «Люди» в соответствии со стилем приложения.
/// Без лишнего пустого пространства сверху и с белой шторкой, уходящей до низа экрана.
struct DebtsView: View {
    let financeService: FinanceService
    @State private var selectedSegment = 0 // 0: Кредиты, 1: Люди
    @State private var isShowingAddSheet = false
    
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.height < 750
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "#0E0F12") // Глубокий темный фон
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Шапка
                headerView
                    .padding(.horizontal, 24)
                    .padding(.top, isSmallScreen ? 12 : 20)
                
                // Переключатель сегментов «Кредиты / Люди»
                customSegmentControl
                    .padding(.horizontal, 24)
                    .padding(.top, isSmallScreen ? 12 : 20)
                    .padding(.bottom, isSmallScreen ? 16 : 24)
                
                // Белая шторка со списком
                debtsBottomSheet
            }
            .ignoresSafeArea(edges: .bottom) // Позволяет белой шторке уходить до низа экрана
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingAddSheet) {
            AddDebtView(financeService: financeService)
        }
    }
    
    // MARK: - Шапка
    private var headerView: some View {
        HStack {
            Text("Debts")
                .font(.system(size: isSmallScreen ? 28 : 32, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            Button {
                HapticManager.shared.impact(.light)
                isShowingAddSheet = true
            } label: {
                Text("Add debt")
                    .font(.system(size: isSmallScreen ? 11 : 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, isSmallScreen ? 12 : 16)
                    .padding(.vertical, isSmallScreen ? 6 : 8)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Переключатель "Кредиты / Люди"
    private var customSegmentControl: some View {
        HStack(spacing: 0) {
            Button {
                HapticManager.shared.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    selectedSegment = 0
                }
            } label: {
                Text("Кредиты")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(selectedSegment == 0 ? .black : .white.opacity(0.45))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(selectedSegment == 0 ? Color.white : Color.clear)
                    .clipShape(Capsule())
            }
            
            Button {
                HapticManager.shared.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    selectedSegment = 1
                }
            } label: {
                Text("Люди")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(selectedSegment == 1 ? .black : .white.opacity(0.45))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(selectedSegment == 1 ? Color.white : Color.clear)
                    .clipShape(Capsule())
            }
        }
        .padding(4)
        .background(Color(hex: "#17181A"))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
    
    // MARK: - Шторка списка
    private var debtsBottomSheet: some View {
        let filteredDebts = financeService.debts.filter { debt in
            if selectedSegment == 0 {
                return debt.type == .credit
            } else {
                return debt.type == .person
            }
        }
        
        return VStack(spacing: 0) {
            if filteredDebts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: selectedSegment == 0 ? "building.columns.fill" : "person.2.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.35))
                        .symbolRenderingMode(.hierarchical)
                    
                    Text("Пусто")
                        .font(.headline)
                        .foregroundColor(.black.opacity(0.6))
                    
                    Text(selectedSegment == 0 ? "У вас нет активных кредитов." : "У вас нет активных долгов людям.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(.rect(topLeadingRadius: isSmallScreen ? 24 : 32, topTrailingRadius: isSmallScreen ? 24 : 32))
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        ForEach(filteredDebts) { debt in
                            DebtRowView(debt: debt, financeService: financeService)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        HapticManager.shared.trigger(.warning)
                                        withAnimation(.spring()) {
                                            financeService.deleteDebt(id: debt.id)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, isSmallScreen ? 90 : 110)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(.rect(topLeadingRadius: isSmallScreen ? 24 : 32, topTrailingRadius: isSmallScreen ? 24 : 32))
            }
        }
    }
}
