import SwiftUI

/// Создание и редактирование карты: данные, оформление и предпросмотр, который меняется на лету
@MainActor
struct CardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let financeService: FinanceService
    /// Карта, которую правят; nil — создаётся новая
    let editing: Card?

    private enum Page: Hashable {
        case details
        case style
    }

    private enum Field: Hashable {
        case purpose, bank, holder, balance, number, expiry
    }

    @State private var page: Page = ScreenshotMode.scene == .cardEditor || ScreenshotMode.isTour ? .style : .details
    @State private var purpose: String
    @State private var bankName: String
    @State private var holderName: String
    @State private var balanceString: String
    @State private var numberText = ""
    @State private var expiryText: String
    /// Платёжная система, выбранная вручную; nil — определять по номеру
    @State private var manualNetwork: CardNetwork?
    @State private var gradient: [String]
    @State private var pattern: CardPattern
    @State private var symbol: String?
    /// Номер из Keychain уже подставлен в поле (при правке карты)
    @State private var hasLoadedNumber = false
    /// Цифры номера, которые лежали в Keychain; по ним видно, менял ли пользователь номер
    @State private var storedDigits = ""
    @State private var showsErrors = false
    @State private var isConfirmingDelete = false
    @FocusState private var focusedField: Field?

    init(financeService: FinanceService, editing: Card? = nil) {
        self.financeService = financeService
        self.editing = editing
        let colors = editing?.gradientColors ?? []
        let startGradient: [String]
        if colors.count >= 2 {
            startGradient = colors
        } else if let single = colors.first {
            startGradient = [single, single]
        } else {
            startGradient = CardPreset.all[0].colors
        }
        _purpose = State(initialValue: editing?.type ?? "")
        _bankName = State(initialValue: editing?.bankName ?? "")
        _holderName = State(initialValue: editing?.holderName ?? "")
        _balanceString = State(initialValue: editing.map { Self.balanceText($0.balance) } ?? "")
        _expiryText = State(initialValue: editing?.expiryDate ?? "")
        _manualNetwork = State(initialValue: editing?.network)
        _gradient = State(initialValue: startGradient)
        _pattern = State(initialValue: editing?.pattern ?? CardPattern.none)
        _symbol = State(initialValue: editing?.symbol)
    }

    // MARK: - Значения полей

    private var isEditing: Bool { editing != nil }

    private var digits: String { CardInput.digits(numberText) }

    /// Система карты: выбранная вручную или определённая по номеру
    private var network: CardNetwork? {
        manualNetwork ?? CardNetwork.detect(from: digits)
    }

    private var parsedBalance: Double? {
        let text = balanceString.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    private var normalizedExpiry: String? { CardInput.normalizedExpiry(expiryText) }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func balanceText(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    private var defaultPurposes: [String] {
        [
            "card_for_gifts".localized,
            "card_for_online".localized,
            "card_for_travel".localized,
            "main_card".localized
        ]
    }

    // MARK: - Проверки

    private var purposeError: String? {
        trimmed(purpose).isEmpty ? String(localized: "Укажите назначение карты") : nil
    }

    private var holderError: String? {
        trimmed(holderName).isEmpty ? String(localized: "Укажите имя держателя") : nil
    }

    private var balanceError: String? {
        parsedBalance == nil ? String(localized: "Введите баланс числом") : nil
    }

    /// При правке номер можно не вводить: тогда он остаётся прежним
    private var numberError: String? {
        if digits.isEmpty {
            return isEditing ? nil : String(localized: "Введите номер карты")
        }
        return CardInput.isValidLength(digits) ? nil : String(localized: "В номере должно быть от 13 до 19 цифр")
    }

    private var expiryError: String? {
        normalizedExpiry == nil ? String(localized: "Срок в формате ММ/ГГ, например 08/29") : nil
    }

    /// Предупреждения не мешают сохранить карту
    private var numberWarnings: [String] {
        guard numberError == nil, !digits.isEmpty else { return [] }
        var result: [String] = []
        if !CardInput.passesLuhn(digits) {
            result.append(String(localized: "Номер не проходит проверку: возможно, в нём опечатка"))
        }
        if digits.count >= 4 {
            let last4 = Card.lastFourDigits(of: digits)
            if financeService.cards.contains(where: { $0.id != editing?.id && $0.last4 == last4 }) {
                result.append(String(localized: "Карта с такими последними цифрами уже есть: СМС могут привязываться не к той карте"))
            }
        }
        return result
    }

    private var expiryWarnings: [String] {
        guard normalizedExpiry != nil, CardInput.isExpired(expiryText) else { return [] }
        return [String(localized: "Срок действия карты истёк")]
    }

    private var isValid: Bool {
        purposeError == nil && holderError == nil && balanceError == nil && numberError == nil && expiryError == nil
    }

    /// Как будет выглядеть карта; пустые поля показаны заглушками
    private var previewCard: Card {
        let name = trimmed(purpose)
        let holder = trimmed(holderName)
        let bank = trimmed(bankName)
        return Card(
            last4: digits.count >= 4 ? Card.lastFourDigits(of: digits) : (editing?.last4 ?? "0000"),
            holderName: holder.isEmpty ? "card_holder".localized : holder,
            balance: parsedBalance ?? 0,
            type: name.isEmpty ? "new_card".localized : name,
            colorHex: gradient[0],
            gradientColors: gradient,
            isFrozen: editing?.isFrozen ?? false,
            expiryDate: normalizedExpiry ?? String(localized: "ММ/ГГ"),
            bankName: bank.isEmpty ? nil : bank,
            network: network,
            pattern: pattern,
            symbol: symbol
        )
    }

    // MARK: - Экран

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MonoSegmentedControl(
                    options: [Page.details, Page.style],
                    title: { pageTitle($0) },
                    selection: $page
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

                if page == .style {
                    // Оформление правят, глядя на карту, поэтому на этой вкладке она закреплена сверху
                    previewView
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }

                Form {
                    if page == .details {
                        detailsSections
                    } else {
                        styleSections
                    }
                }
                .monoForm()
                .scrollDismissesKeyboard(.interactively)
            }
            .monoScreen()
            .navigationTitle(isEditing ? String(localized: "Правка карты") : "new_card".localized)
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
                String(localized: "Удалить карту?"),
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("delete_card".localized, role: .destructive) {
                    deleteCard()
                }
                Button("cancel".localized, role: .cancel) {}
            } message: {
                Text(String(localized: "Накопительные цели этой карты тоже будут удалены."))
            }
            .onAppear {
                loadStoredNumber()
            }
            #if DEBUG
            .task {
                await playTour()
            }
            #endif
            .onChange(of: numberText) { _, newValue in
                let formatted = CardInput.formatNumber(newValue, network: network)
                if formatted != newValue {
                    numberText = formatted
                }
            }
            .onChange(of: expiryText) { _, newValue in
                let formatted = CardInput.formatExpiry(newValue)
                if formatted != newValue {
                    expiryText = formatted
                }
            }
        }
    }

    #if DEBUG
    /// Ролик App Store: цвет, узор и значок меняются сами, карта сверху отвечает на каждое изменение
    private func playTour() async {
        guard ScreenshotMode.isTour else { return }
        try? await Task.sleep(for: .milliseconds(900))
        let steps: [(String, CardPattern, String)] = [
            ("ocean", CardPattern.waves, "airplane"),
            ("violet", CardPattern.dots, "gift.fill"),
            ("sunset", CardPattern.lines, "cart.fill")
        ]
        for step in steps {
            withAnimation(Motion.bouncy) {
                gradient = CardPreset.all.first { $0.id == step.0 }?.colors ?? gradient
                pattern = step.1
                symbol = step.2
            }
            try? await Task.sleep(for: .milliseconds(1100))
        }
    }
    #endif

    private func pageTitle(_ page: Page) -> String {
        page == .details ? String(localized: "Данные") : String(localized: "Оформление")
    }

    private var previewView: some View {
        CardItemView(card: previewCard)
            .animation(Motion.spring, value: gradient)
            .animation(Motion.spring, value: pattern)
            .animation(Motion.spring, value: symbol)
    }

    // MARK: - Вкладка «Данные»

    @ViewBuilder
    private var detailsSections: some View {
        Section {
            previewView
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }

        Section {
            VStack(alignment: .leading, spacing: 6) {
                TextField("card_purpose".localized, text: $purpose)
                    .focused($focusedField, equals: .purpose)
                notes(error: showsErrors ? purposeError : nil)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(defaultPurposes, id: \.self) { option in
                        optionChip(title: option, isSelected: purpose == option) {
                            purpose = option
                        }
                    }
                }
            }

            TextField(String(localized: "Банк (необязательно)"), text: $bankName)
                .focused($focusedField, equals: .bank)
        } header: {
            Text("card_purpose".localized)
        } footer: {
            Text(String(localized: "Название банка появится на карте под назначением."))
        }

        Section {
            VStack(alignment: .leading, spacing: 6) {
                TextField("card_holder".localized, text: $holderName)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .holder)
                notes(error: showsErrors ? holderError : nil)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "Баланс (\(CurrencyManager.shared.baseCurrency.symbol))"))
                    Spacer()
                    TextField("0", text: $balanceString)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .balance)
                }
                notes(error: showsErrors ? balanceError : nil)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("full_card_number".localized)
                    Spacer()
                    TextField("0000 0000 0000 0000", text: $numberText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($focusedField, equals: .number)
                }
                notes(error: showsErrors ? numberError : nil, warnings: numberWarnings)
                if isEditing && hasLoadedNumber && storedDigits.isEmpty && digits.isEmpty {
                    Text(String(localized: "Номер не сохранён на этом устройстве. Введите его снова, если хотите сохранить."))
                        .font(.footnote)
                        .foregroundColor(Theme.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("expiry_date".localized)
                    Spacer()
                    TextField(String(localized: "ММ/ГГ"), text: $expiryText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($focusedField, equals: .expiry)
                }
                notes(error: showsErrors ? expiryError : nil, warnings: expiryWarnings)
            }
        } header: {
            Text("card_requisites".localized)
        } footer: {
            Text(String(localized: "Полный номер хранится только в защищённом хранилище этого устройства. Код CVV приложение не сохраняет."))
        }

        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    optionChip(title: autoNetworkTitle, isSelected: manualNetwork == nil) {
                        manualNetwork = nil
                    }
                    ForEach(CardNetwork.allCases) { option in
                        optionChip(title: option.title, isSelected: manualNetwork == option) {
                            manualNetwork = option
                        }
                    }
                }
            }
        } header: {
            Text(String(localized: "Платёжная система"))
        } footer: {
            Text(String(localized: "По умолчанию определяется по номеру. ArCa по номеру не определить, выберите её вручную."))
        }

        if isEditing {
            Section {
                Button(role: .destructive) {
                    HapticManager.shared.trigger(.warning)
                    isConfirmingDelete = true
                } label: {
                    Text("delete_card".localized)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var autoNetworkTitle: String {
        let auto = String(localized: "Авто")
        guard let detected = CardNetwork.detect(from: digits) else { return auto }
        return "\(auto) · \(detected.title)"
    }

    /// Сообщения под полем: ошибка красным, предупреждения оранжевым
    @ViewBuilder
    private func notes(error: String?, warnings: [String] = []) -> some View {
        if let error {
            Text(error)
                .font(.footnote)
                .foregroundColor(Color.red)
        }
        ForEach(warnings, id: \.self) { warning in
            Text(warning)
                .font(.footnote)
                .foregroundColor(Color.orange)
        }
    }

    /// Капсула выбора: назначение карты, платёжная система
    private func optionChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(Motion.spring) {
                action()
            }
        } label: {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(isSelected ? Theme.onAccent : .white)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(isSelected ? Theme.accent : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Вкладка «Оформление»

    @ViewBuilder
    private var styleSections: some View {
        Section {
            PresetSwatchRow(gradient: $gradient)

            ColorPicker(String(localized: "Первый цвет"), selection: colorBinding(0), supportsOpacity: false)
            ColorPicker(String(localized: "Второй цвет"), selection: colorBinding(1), supportsOpacity: false)

            Button {
                HapticManager.shared.impact(.light)
                withAnimation(Motion.spring) {
                    gradient.reverse()
                }
            } label: {
                Label(String(localized: "Поменять цвета местами"), systemImage: "arrow.left.arrow.right")
            }
        } header: {
            Text("card_color_theme".localized)
        }

        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CardPattern.allCases) { option in
                        patternTile(option)
                    }
                }
                .padding(.vertical, 6)
            }
        } header: {
            Text(String(localized: "Узор"))
        }

        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(symbolOptions, id: \.self) { name in
                        symbolButton(name)
                    }
                }
                .padding(.vertical, 6)
            }
        } header: {
            Text(String(localized: "Значок"))
        } footer: {
            Text(String(localized: "Значок появится рядом с назначением карты."))
        }
    }

    private var symbolOptions: [String?] {
        [nil] + CardSymbol.all.map { Optional($0) }
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { Color(hex: gradient[index]) },
            set: { gradient[index] = $0.hexString }
        )
    }

    private func patternTile(_ option: CardPattern) -> some View {
        let isSelected = pattern == option
        let ink: Color = Theme.isLight(hex: gradient[0]) ? .black : .white
        return Button {
            HapticManager.shared.selection()
            withAnimation(Motion.spring) {
                pattern = option
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    LinearGradient(colors: gradient.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                    CardPatternView(pattern: option, color: ink)
                }
                .frame(width: 76, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Theme.accent : Theme.line, lineWidth: isSelected ? 2 : 1)
                )
                Text(option.title)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? Color.white : Theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func symbolButton(_ name: String?) -> some View {
        let isSelected = symbol == name
        return Button {
            HapticManager.shared.selection()
            withAnimation(Motion.spring) {
                symbol = name
            }
        } label: {
            Image(systemName: name ?? "nosign")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isSelected ? Theme.onAccent : .white)
                .frame(width: 44, height: 44)
                .background(isSelected ? Theme.accent : Theme.surfaceRaised)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CardSymbol.title(name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Действия

    /// При правке подставляет полный номер из Keychain; если его там нет, поле остаётся пустым
    private func loadStoredNumber() {
        guard let card = editing, !hasLoadedNumber else { return }
        hasLoadedNumber = true
        guard let stored = financeService.cardNumber(for: card.id), !stored.isEmpty else { return }
        storedDigits = CardInput.digits(stored)
        numberText = CardInput.formatNumber(stored, network: card.network)
        // Если система совпадает с определяемой по номеру, пусть и дальше определяется сама
        if let detected = CardNetwork.detect(from: storedDigits), detected == card.network {
            manualNetwork = nil
        }
    }

    private func save() {
        guard isValid, let balance = parsedBalance, let expiry = normalizedExpiry else {
            showsErrors = true
            page = .details
            HapticManager.shared.trigger(.error)
            return
        }
        let colors = gradient
        let bank = trimmed(bankName)

        if var card = editing {
            card.type = trimmed(purpose)
            card.holderName = trimmed(holderName)
            card.balance = balance
            card.expiryDate = expiry
            card.bankName = bank.isEmpty ? nil : bank
            card.network = network
            card.pattern = pattern == CardPattern.none ? nil : pattern
            card.symbol = symbol
            card.colorHex = colors[0]
            card.gradientColors = colors
            let changedNumber = !digits.isEmpty && digits != storedDigits
            financeService.updateCard(card, number: changedNumber ? digits : nil)
        } else {
            let card = Card(
                last4: Card.lastFourDigits(of: digits),
                holderName: trimmed(holderName),
                balance: balance,
                type: trimmed(purpose),
                colorHex: colors[0],
                gradientColors: colors,
                isFrozen: false,
                expiryDate: expiry,
                bankName: bank.isEmpty ? nil : bank,
                network: network,
                pattern: pattern == CardPattern.none ? nil : pattern,
                symbol: symbol
            )
            financeService.addCard(card, number: digits)
        }
        HapticManager.shared.trigger(.success)
        dismiss()
    }

    private func deleteCard() {
        guard let card = editing else { return }
        financeService.deleteCard(id: card.id)
        HapticManager.shared.trigger(.success)
        dismiss()
    }
}
