import SwiftUI

/// Экран настроек приложения. Позволяет сбросить все транзакции с подтверждением и тактильной отдачей.
struct SettingsView: View {
    let financeService: FinanceService
    @State private var isShowingDeleteAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.accentColor)
                            .symbolRenderingMode(.hierarchical)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Пользователь SamFinance")
                                .font(.headline)
                            Text("Тариф: Premium")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Профиль")
                }
                
                Section {
                    HStack {
                        Label("Основная валюта", systemImage: "rublesign.circle.fill")
                        Spacer()
                        Text("Рубль (₽)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Экспорт данных", systemImage: "doc.arrow.up.fill")
                        Spacer()
                        Text("CSV")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Предпочтения")
                }
                
                Section {
                    Button(role: .destructive) {
                        HapticManager.shared.trigger(.warning)
                        isShowingDeleteAlert = true
                    } label: {
                        Label("Сбросить все данные", systemImage: "trash.fill")
                    }
                } header: {
                    Text("Опасная зона")
                } footer: {
                    Text("Все транзакции будут безвозвратно удалены из памяти устройства.")
                }
            }
            .navigationTitle("Настройки")
            .confirmationDialog(
                "Вы уверены, что хотите сбросить все данные?",
                isPresented: $isShowingDeleteAlert,
                titleVisibility: .visible
            ) {
                Button("Очистить все", role: .destructive) {
                    resetAllData()
                }
                Button("Отмена", role: .cancel) {
                    HapticManager.shared.impact(.light)
                }
            }
        }
    }
    
    private func resetAllData() {
        // Очищаем через удаление каждой транзакции или добавим метод очистки в FinanceService.
        // Поскольку у нас есть удаление по IndexSet, удалим все транзакции.
        for t in financeService.transactions {
            financeService.deleteTransaction(t)
        }
        HapticManager.shared.trigger(.success)
    }
}
