import SwiftUI

/// Главный контейнер приложения, управляющий вкладками (Дашборд и Настройки).
struct ContentView: View {
    @State private var financeService = FinanceService()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(financeService: financeService)
                .tabItem {
                    Label("Главная", systemImage: "house.fill")
                }
                .tag(0)
            
            SettingsView(financeService: financeService)
                .tabItem {
                    Label("Настройки", systemImage: "gearshape.fill")
                }
                .tag(1)
        }
        .onChange(of: selectedTab) {
            HapticManager.shared.selection()
        }
    }
}
