import PhotosUI
import SwiftUI

/// Раздел «ИИ»: чат, куда можно прислать скриншоты СМС или текст, а помощник разложит операции по картам и категориям.
@MainActor
struct AIChatView: View {
    let financeService: FinanceService
    @State private var store = AIChatStore.shared
    @State private var inputText = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isShowingSettings = false
    /// Счётчик отправок: по нему подпрыгивает стрелка
    @State private var sendCount = 0
    @FocusState private var isInputFocused: Bool

    private static let bottomID = "chat-bottom"

    var body: some View {
        VStack(spacing: 0) {
            headerView
            messagesView
            inputBar
        }
        .monoScreen()
        .onAppear {
            store.refreshCloudState()
        }
        .alert(
            "Отправить данные в \(store.pendingConsent?.provider.company ?? "")?",
            isPresented: consentBinding,
            presenting: store.pendingConsent
        ) { _ in
            Button("Разрешить и отправить") {
                store.grantConsent()
            }
            Button("Не отправлять", role: .cancel) {
                store.declineConsent()
            }
        } message: { request in
            Text(request.provider.consentMessage)
        }
        .sheet(isPresented: $isShowingSettings, onDismiss: {
            store.refreshCloudState()
        }) {
            SettingsView(financeService: financeService)
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            store.send(screenshots: items)
        }
    }

    /// Окно согласия видно, пока в чате есть запрос без ответа; закрытие без выбора считается отказом
    private var consentBinding: Binding<Bool> {
        Binding(
            get: { store.pendingConsent != nil },
            set: { isShown in
                if !isShown {
                    store.declineConsent()
                }
            }
        )
    }

    // MARK: - Шапка
    private var headerView: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ИИ-помощник")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(store.isCloudEnabled ? String(localized: "\(store.provider.statusTitle) · СМС распознаются на телефоне") : String(localized: "Без ключа \(store.provider.displayName): всё считается на телефоне"))
                    .font(.system(size: 13))
                    .foregroundColor(store.isCloudEnabled ? Theme.accent : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            if !store.isFresh {
                MonoCircleButton(systemName: "arrow.counterclockwise", label: String(localized: "Начать заново")) {
                    HapticManager.shared.impact(.light)
                    withAnimation { store.reset() }
                }
            }
            MonoCircleButton(systemName: "key", label: String(localized: "Выбор ИИ и ключ в настройках")) {
                HapticManager.shared.impact(.light)
                isShowingSettings = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Переписка
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.messages) { message in
                        messageView(message)
                            .transition(messageTransition(for: message))
                    }
                    if store.isWorking {
                        workingIndicator
                            .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
                    }
                    if store.isFresh {
                        suggestions
                            .transition(.opacity)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .animation(Motion.spring, value: store.messages.count)
                .animation(Motion.spring, value: store.isWorking)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: store.messages.count) {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
            .onChange(of: store.isWorking) {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
        }
    }

    /// Сообщение выплывает снизу из своего угла: пользователя — справа, помощника — слева
    private func messageTransition(for message: ChatMessage) -> AnyTransition {
        let anchor: UnitPoint = message.role == .user ? .bottomTrailing : .bottomLeading
        return .asymmetric(
            insertion: .scale(scale: 0.85, anchor: anchor)
                .combined(with: .opacity)
                .combined(with: .offset(y: 12)),
            removal: .opacity
        )
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            Group {
                if message.thumbnails.isEmpty {
                    bubble(message.text, isUser: true)
                } else {
                    thumbnailsRow(message.thumbnails)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 48)
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                bubble(message.text, isUser: false)
                if let draft = message.draft {
                    DraftCard(store: store, messageID: message.id, draft: draft, financeService: financeService)
                }
                if let actionDraft = message.actionDraft {
                    ActionDraftCard(store: store, messageID: message.id, draft: actionDraft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, message.draft == nil && message.actionDraft == nil ? 48 : 0)
        }
    }

    private func bubble(_ text: String, isUser: Bool) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundColor(isUser ? Theme.onAccent : .white)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isUser ? Theme.accent : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func thumbnailsRow(_ images: [UIImage]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(images.prefix(4).enumerated()), id: \.offset) { index, image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        if index == 3 && images.count > 4 {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.black.opacity(0.55))
                            Text("+\(images.count - 3)")
                                .font(Theme.number(18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(images.count == 1 ? String(localized: "Скриншот") : String(localized: "Скриншотов: \(images.count)"))
    }

    private var workingIndicator: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.accent)
                .symbolEffect(.pulse)
            Text(store.workingText ?? "")
                .font(.system(size: 15))
                .foregroundColor(Theme.textSecondary)
            Button {
                HapticManager.shared.impact(.light)
                store.cancelWork()
            } label: {
                Text("Отмена")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 32)
            }
            .accessibilityLabel(String(localized: "Отменить запрос"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Подсказки
    private var suggestions: some View {
        var questions = [
            String(localized: "Сколько я потратил за неделю?"),
            String(localized: "Сколько ушло на продукты за месяц?"),
            String(localized: "Какой у меня баланс?"),
            String(localized: "Кому я должен?"),
            String(localized: "Дай совет")
        ]
        // Фразы о тратах и просьбы что-то изменить в приложении понимает только облачный ИИ
        if store.isCloudEnabled {
            questions.insert(String(localized: "Вчера потратил 3 000 на такси"), at: 0)
            questions.insert(String(localized: "Добавь долг: Арам должен мне 20 000 до конца месяца"), at: 1)
            questions.insert(String(localized: "Напомни в пятницу в 10:00 оплатить интернет"), at: 2)
        }
        return VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                Label("Загрузить скриншоты СМС", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.onAccent)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.pressable)
            .appearAnimation(order: 1)
            ForEach(Array(questions.enumerated()), id: \.element) { index, question in
                Button {
                    HapticManager.shared.impact(.light)
                    store.send(text: question)
                } label: {
                    Text(question)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Theme.surfaceRaised)
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
                .appearAnimation(order: index + 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Поле ввода
    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isWorking
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.surfaceRaised)
                    .clipShape(Circle())
            }
            .disabled(store.isWorking)
            .accessibilityLabel("Прислать скриншоты")

            TextField("Вопрос или текст СМС", text: $inputText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .tint(Theme.accent)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 22))

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.onAccent)
                    .symbolEffect(.bounce.up, value: sendCount)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.88))
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.4)
            .scaleEffect(canSend ? 1 : 0.9)
            .animation(Motion.bouncy, value: canSend)
            .accessibilityLabel("Отправить")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.background)
    }

    private func send() {
        guard canSend else { return }
        HapticManager.shared.impact(.light)
        sendCount += 1
        store.send(text: inputText)
        inputText = ""
    }
}

/// Карточка черновика: найденные операции с отметками, категориями и кнопкой «Записать»
@MainActor
private struct DraftCard: View {
    let store: AIChatStore
    let messageID: UUID
    let draft: OperationDraft
    let financeService: FinanceService

    var body: some View {
        VStack(spacing: 0) {
            ForEach(draft.items) { item in
                row(item)
                if item.id != draft.items.last?.id {
                    MonoDivider()
                }
            }

            if draft.isSaved {
                Label("Записано", systemImage: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .symbolEffect(.bounce, value: draft.isSaved)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                let count = draft.includedCount
                PrimaryButton(title: count > 0 ? String(localized: "Записать (\(count))") : String(localized: "Ничего не отмечено"), isEnabled: count > 0) {
                    store.saveDraft(in: messageID)
                }
                .padding(.top, 12)
            }
        }
        .padding(14)
        .monoSurface(cornerRadius: 24)
        .animation(Motion.spring, value: draft.isSaved)
    }

    private func row(_ item: DraftItem) -> some View {
        let parsed = item.parsed
        let isIncome = parsed.type == .income
        return HStack(alignment: .center, spacing: 12) {
            Button {
                HapticManager.shared.selection()
                store.toggle(itemID: item.id, in: messageID)
            } label: {
                Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(item.isIncluded ? Theme.accent : Theme.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .disabled(draft.isSaved)
            .accessibilityLabel(item.isIncluded ? String(localized: "Не записывать") : String(localized: "Записать"))

            VStack(alignment: .leading, spacing: 3) {
                Text(parsed.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                categoryMenu(item)
                Text(details(item))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(isIncome ? "+" : "−")\(CurrencyManager.shared.format(item.amountInBase))")
                .font(Theme.number(15))
                .foregroundColor(isIncome ? Theme.accent : .white)
                .lineLimit(1)
        }
        .opacity(item.isIncluded || draft.isSaved ? 1 : 0.5)
        .animation(Motion.spring, value: item.isIncluded)
        .padding(.vertical, 4)
    }

    /// Категория с выбором: ручной выбор запоминается для магазина
    private func categoryMenu(_ item: DraftItem) -> some View {
        let current = item.category
        return Menu {
            ForEach(financeService.categories.filter { $0.type == item.parsed.type }) { category in
                Button {
                    store.setCategory(category, itemID: item.id, in: messageID)
                } label: {
                    Label(category.displayName, systemImage: category.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current.displayName)
                if item.needsReview {
                    Text("· проверьте")
                        .foregroundColor(Theme.accent)
                }
                if !draft.isSaved {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .font(.system(size: 13))
            .foregroundColor(Theme.textSecondary)
        }
        .disabled(draft.isSaved)
    }

    private func details(_ item: DraftItem) -> String {
        var parts: [String] = []
        if let last4 = item.parsed.cardLast4 {
            parts.append("•••• \(last4)")
        }
        if let date = item.parsed.date {
            parts.append(date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
        }
        if item.isDuplicate {
            parts.append(String(localized: "уже записана"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Карточка изменений, которые предложил ИИ: каждое можно снять, удаление выделено красным, нельзя применить только то, что не нашлось
@MainActor
private struct ActionDraftCard: View {
    let store: AIChatStore
    let messageID: UUID
    let draft: ActionDraft

    var body: some View {
        VStack(spacing: 0) {
            ForEach(draft.items) { item in
                row(item)
                if item.id != draft.items.last?.id {
                    MonoDivider()
                }
            }

            if draft.isApplied {
                Label("Применено", systemImage: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .symbolEffect(.bounce, value: draft.isApplied)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                let count = draft.includedCount
                PrimaryButton(title: count > 0 ? String(localized: "Применить (\(count))") : String(localized: "Ничего не отмечено"), isEnabled: count > 0) {
                    store.applyActions(in: messageID)
                }
                .padding(.top, 12)
            }
        }
        .padding(14)
        .monoSurface(cornerRadius: 24)
        .animation(Motion.spring, value: draft.isApplied)
    }

    private func row(_ item: ActionItem) -> some View {
        let plan = item.plan
        let tint = plan.isDestructive ? Theme.danger : Theme.accent
        return HStack(alignment: .center, spacing: 12) {
            Button {
                HapticManager.shared.selection()
                store.toggleAction(itemID: item.id, in: messageID)
            } label: {
                Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(item.isIncluded ? tint : Theme.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .disabled(draft.isApplied || !plan.canApply)
            .accessibilityLabel(item.isIncluded ? String(localized: "Не применять") : String(localized: "Применить"))

            Image(systemName: plan.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(plan.canApply ? tint : Theme.textSecondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(plan.summary)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(plan.canApply ? .white : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let problem = plan.problem {
                    Text(problem)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if case .failed(let reason)? = item.outcome {
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .opacity(item.isIncluded || draft.isApplied ? 1 : 0.5)
        .padding(.vertical, 4)
    }
}
