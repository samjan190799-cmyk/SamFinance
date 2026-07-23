import SwiftUI

/// Экран настроек приложения. Позволяет управлять данными, экспортировать информацию и сбрасывать состояние.
struct SettingsView: View {
    let financeService: FinanceService
    @State private var isShowingDeleteAlert = false
    @State private var exportMessage: String? = nil
    
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
                            Text("Тариф: Premium Pro")
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
                        Label("Основная валюта", systemImage: "dollarsign.circle.fill")
                        Spacer()
                        Text("USD ($)")
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        HapticManager.shared.trigger(.success)
                        exportDataToClipboard()
                    } label: {
                        HStack {
                            Label("Экспорт данных", systemImage: "doc.arrow.up.fill")
                            Spacer()
                            Text(exportMessage ?? "Скопировать CSV")
                                .foregroundColor(exportMessage != nil ? .green : .secondary)
                        }
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
                    Text("Все карты, транзакции, долги и накопительные цели будут очищены из памяти.")
                }
            }
            .navigationTitle("Настройки")
            .confirmationDialog(
                "Вы уверены, что хотите сбросить все данные?",
                isPresented: $isShowingDeleteAlert,
                titleVisibility: .visible
            ) {
                Button("Очистить полностью", role: .destructive) {
                    resetAllData()
                }
                Button("Отмена", role: .cancel) {
                    HapticManager.shared.impact(.light)
                }
            }
        }
    }
    
    private func exportDataToClipboard() {
        var csvText = "Date,Type,Category,Title,Amount\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        for t in financeService.transactions {
            let dateStr = formatter.string(from: t.date)
            csvText += "\(dateStr),\(t.type.rawValue),\(t.category.name),\(t.title),\(t.amount)\n"
        }
        
        UIPasteboard.general.string = csvText
        withAnimation {
            exportMessage = "Скопировано в буфер!"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            exportMessage = nil
        }
    }
    
    private func resetAllData() {
        // Очищаем транзакции
        for t in financeService.transactions {
            financeService.deleteTransaction(t)
        }
        // Очищаем карты
        for c in financeService.cards {
            financeService.deleteCard(id: c.id)
        }
        // Очищаем долги
        for d in financeService.debts {
            financeService.deleteDebt(id: d.id)
        }
        // Очищаем копилки
        for g in financeService.goals {
            financeService.deleteGoal(id: g.id)
        }
        
        HapticManager.shared.trigger(.success)
    }
}
