import Foundation

/// Ответы ИИ-чата на вопросы о деньгах. Считает по данным на телефоне, без сети:
/// траты по категории и периоду, доходы, баланс карт, долги и советы.
/// Вопрос понимается на русском, английском, армянском и ещё на десятке языков (украинский, испанский, французский, немецкий,
/// итальянский, португальский, турецкий, польский, арабский, китайский, японский, корейский, грузинский) независимо от языка
/// интерфейса; ответ — на языке интерфейса. Названия категорий узнаются не на всех языках. Остальное разбирает облачный ИИ.
@MainActor
enum LocalFinanceAssistant {

    static func answer(_ question: String, financeService: FinanceService) -> String {
        let text = question.lowercased()
        let period = period(in: text)

        if containsAny(text, Words.goals) {
            return goalsAnswer(financeService)
        }
        if containsAny(text, Words.subscriptions) {
            return subscriptionsAnswer(financeService)
        }
        if containsAny(text, Words.balance) {
            return balanceAnswer(financeService)
        }
        if containsAny(text, Words.debts) {
            return debtsAnswer(financeService)
        }
        if containsAny(text, Words.advice) {
            return adviceAnswer(financeService)
        }
        if containsAny(text, Words.income) {
            return incomeAnswer(period: period, financeService: financeService)
        }
        if let category = category(in: text, financeService: financeService) {
            return categoryAnswer(category, period: period, financeService: financeService)
        }
        if containsAny(text, Words.spending) {
            return spendingAnswer(period: period, financeService: financeService)
        }
        return helpText
    }

    static var helpText: String {
        String(localized: "Пока я понимаю скриншоты и тексты банковских СМС и такие вопросы:\n• сколько я потратил за неделю?\n• сколько ушло на продукты за месяц?\n• какой у меня баланс?\n• кому я должен?\n• дай совет\n• как мои копилки?")
    }

    // MARK: - Слова из вопроса (корни слов: русский, английский, армянский и ещё десяток языков)

    private enum Words {
        static let goals: [String] = [
            "копилк", "накопл", "накопил", "моя цель", "мои цели",
            "goal", "piggy", "have i saved",
            "նպատակ", "խնայարկղ",
            "скарбничк", "мої цілі", "mis metas", "hucha", "mes objectifs", "tirelire", "sparziel", "spardose",
            "obiettiv", "salvadanaio", "meus objetivos", "cofrinho", "birikim", "kumbara", "skarbonk", "cele oszczędn",
            "أهدافي", "الادخار", "储蓄目标", "存钱", "貯金", "저축", "დანაზოგ"
        ]
        static let subscriptions: [String] = [
            "подписк", "subscription", "բաժանորդագր",
            "підписк", "suscripci", "abonnement", "abos", "abbonament", "assinatura", "abonelik", "subskrypcj", "abonament",
            "اشتراك", "订阅", "サブスク", "定期購読", "구독", "გამოწერ"
        ]
        static let balance: [String] = [
            "баланс", "сколько денег", "на картах", "на карте", "остаток",
            "balance", "how much money", "money do i have", "on my cards", "on the card",
            "հաշվեկշիռ", "մնացորդ", "որքան գումար", "քարտերի վրա", "քարտի վրա",
            "залишок", "скільки грошей", "на картках", "на картці",
            "saldo", "cuánto dinero", "cuanto dinero", "en mis tarjetas", "en la tarjeta",
            "solde", "combien d'argent", "sur mes cartes", "sur la carte",
            "kontostand", "guthaben", "wie viel geld", "auf meinen karten", "auf der karte",
            "quanti soldi", "sulle mie carte", "sulla carta",
            "quanto dinheiro", "nos meus cartões", "no cartão",
            "bakiye", "ne kadar param", "kartlarımda", "kartımda",
            "stan konta", "ile mam pieniędzy", "na kartach", "na karcie",
            "رصيد", "كم لدي", "في بطاقاتي", "余额", "我有多少钱", "卡里有多少", "残高", "いくらある", "잔액", "잔고",
            "ბალანსი", "ნაშთი", "რამდენი ფული"
        ]
        static let debts: [String] = [
            "долг", "должен", "должна", "должны", "одолжил", "занял",
            "debt", "owe", "borrow", "lent", "loan",
            "պարտք", "վարկ",
            "платёж", "платеж", "коммунал", "bill", "utilit", "վճարում",
            "борг", "винен", "заборгован", "позичив",
            "deuda", "me deben", "préstamo", "dette", "je dois", "on me doit", "prêt",
            "schulden", "ich schulde", "kredit", "debiti", "debito", "mi devono", "prestito",
            "dívida", "eu devo", "me devem", "empréstimo", "borç", "dług", "dłużn", "pożyczk",
            "ديون", "مدين", "债", "欠", "借金", "ローン", "빚", "부채", "대출", "ვალი", "სესხი"
        ]
        static let advice: [String] = [
            "совет", "анализ", "рекоменд", "сэконом", "экономить",
            "advice", "tips", "a tip", "analy", "recommend", "saving",
            "խորհուրդ", "վերլուծ", "խնայ",
            "порад", "аналіз", "consejo", "análisis", "conseil", "recommand", "ratschlag", "tipp", "empfehl",
            "consigli", "raccomand", "conselho", "análise", "tavsiye", "öneri", "rekomend",
            "نصيحة", "نصائح", "تحليل", "建议", "分析", "アドバイス", "提案", "조언", "분석", "რჩევა", "ანალიზი"
        ]
        static let income: [String] = [
            "доход", "заработ", "получил", "зарплат", "пришло",
            "income", "earn", "received", "salary", "got paid",
            "եկամուտ", "ստացել", "աշխատավարձ", "վաստակ",
            "дохід", "заробив", "отримав",
            "ingreso", "gané", "cobré", "salario", "sueldo", "revenu", "gagné", "salaire", "reçu",
            "einkommen", "einnahmen", "verdient", "gehalt", "entrate", "guadagn", "stipendio", "reddito",
            "ganhei", "salário", "gelir", "kazandım", "maaş", "dochód", "dochod", "zarobi", "wynagrodz",
            "راتب", "كسبت", "收入", "工资", "赚", "収入", "給料", "稼", "수입", "월급", "급여", "შემოსავალ", "ხელფას"
        ]
        static let spending: [String] = [
            "потрат", "расход", "трат", "ушло", "сколько",
            "spent", "spend", "expens", "how much", "cost",
            "ծախս", "գնացել", "որքան",
            "витрат", "скільки",
            "gast", "cuánto", "cuanto", "dépens", "depens", "combien",
            "ausgab", "ausgegeben", "wie viel", "wieviel", "spes", "quanto",
            "harcad", "harcama", "gider", "ne kadar", "wydał", "wydal", "wydat",
            "أنفقت", "مصروف", "صرفت", "花了", "支出", "花费", "消费", "使った", "出費", "지출", "썼", "소비", "დავხარჯე", "ხარჯ"
        ]
        static let today: [String] = [
            "сегодня", "today", "այսօր",
            "сьогодні", "hoy", "aujourd", "heute", "oggi", "hoje", "bugün", "dzisiaj", "dziś",
            "اليوم", "今天", "今日", "오늘", "დღეს"
        ]
        static let week: [String] = [
            "недел", "week", "շաբաթ",
            "тижд", "semana", "semaine", "woche", "settimana", "hafta", "tygod", "tydzie",
            "أسبوع", "周", "星期", "週", "이번 주", "주간", "კვირა"
        ]
        static let allTime: [String] = [
            "всё время", "все время", "за всё", "за все", "всего",
            "all time", "ever", "in total",
            "ողջ ժամանակ", "ամբողջ ժամանակ",
            "весь час", "за весь", "todo el tiempo", "en total", "siempre", "depuis toujours", "au total",
            "insgesamt", "gesamt", "in totale", "sempre", "todo o tempo", "no total", "toplam", "her zaman",
            "łącznie", "od zawsze", "الإجمالي", "طوال الوقت", "总共", "所有时间", "一共", "合計", "全期間", "총", "სულ", "მთლიანად"
        ]
    }

    private static func containsAny(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    /// Период из вопроса; если не назван, считаем за 30 дней
    private static func period(in text: String) -> TimePeriodFilter {
        if containsAny(text, Words.today) { return .today }
        if containsAny(text, Words.week) { return .week }
        if containsAny(text, Words.allTime) { return .allTime }
        return .month
    }

    private static func phrase(for period: TimePeriodFilter) -> String {
        switch period {
        case .today: return String(localized: "Сегодня")
        case .week: return String(localized: "За неделю")
        case .month: return String(localized: "За 30 дней")
        case .allTime: return String(localized: "За всё время")
        }
    }

    /// Слова, по которым узнаём встроенные категории расходов (по их русским названиям)
    private static let categoryWords: [String: [String]] = [
        "Продукты": [
            "продукт", "супермаркет", "магазин", "grocer", "supermarket", "store", "մթերք", "սուպերմարկետ", "խանութ",
            "supermercado", "comestible", "supermarché", "épicerie", "courses", "supermarkt", "lebensmittel", "supermercato", "alimentari",
            "mercearia", "market", "bakkal", "gıda", "spożywcz", "سوبرماركت", "بقالة", "超市", "杂货", "食品", "スーパー", "食料品",
            "슈퍼", "마트", "식료품", "სუპერმარკეტ", "პროდუქტ"
        ],
        "Транспорт": [
            "транспорт", "такси", "бензин", "топлив", "метро", "машин", "transport", "taxi", "fuel", "petrol", "on gas", "for gas", "gas station", "metro",
            "տրանսպորտ", "տաքսի", "վառելիք", "բենզին", "մետրո", "մեքենա",
            "таксі", "пальне", "gasolina", "combustible", "essence", "carburant", "verkehr", "benzin", "kraftstoff", "trasporti", "benzina",
            "carburante", "combustível", "ulaşım", "taksi", "akaryakıt", "taksówk", "paliwo", "benzyn",
            "مواصلات", "تاكسي", "بنزين", "وقود", "交通", "打车", "汽油", "地铁", "タクシー", "ガソリン", "電車", "교통", "택시", "휘발유", "주유",
            "ტრანსპორტ", "ტაქსი", "ბენზინ"
        ],
        "Рестораны": [
            "ресторан", "кафе", "кофе", "обед", "ужин", "доставк", "restaurant", "cafe", "coffee", "lunch", "dinner", "delivery",
            "ռեստորան", "սրճարան", "սուրճ", "ճաշ", "ընթրիք", "առաքում",
            "кава", "обід", "restaurante", "café", "almuerzo", "déjeuner", "dîner", "livraison", "mittagessen", "abendessen",
            "ristorante", "caffè", "pranzo", "almoço", "jantar", "restoran", "kafe", "kahve", "yemek", "restauracj", "kawiarni", "obiad",
            "مطعم", "مقهى", "قهوة", "غداء", "餐厅", "咖啡", "午餐", "晚餐", "外卖", "レストラン", "カフェ", "ランチ", "外食",
            "식당", "카페", "커피", "점심", "რესტორან", "კაფე", "ყავა"
        ],
        "Жилье": [
            "жиль", "квартир", "аренд", "коммунал", "интернет", "связь", "housing", "rent", "utilit", "apartment", "internet", "phone bill",
            "բնակարան", "վարձ", "կոմունալ", "ինտերնետ",
            "житло", "оренд", "alquiler", "vivienda", "hipoteca", "loyer", "logement", "miete", "wohnung", "nebenkosten", "affitto", "bollette",
            "aluguel", "aluguer", "moradia", "kira", "konut", "fatura", "czynsz", "mieszkani", "rachunki",
            "إيجار", "سكن", "فواتير", "房租", "住房", "水电", "网络", "家賃", "住居", "光熱費", "월세", "집세", "공과금", "ქირა", "კომუნალურ"
        ],
        "Развлечения": [
            "развлеч", "кино", "игр", "подписк", "entertain", "movie", "cinema", "game", "subscription", "ժամանց", "կինո", "խաղ", "բաժանորդագր",
            "розваг", "кіно", "entretenimiento", "cine", "juegos", "divertissement", "cinéma", "loisirs", "unterhaltung", "kino", "freizeit",
            "intrattenimento", "giochi", "jogos", "lazer", "eğlence", "sinema", "oyun", "rozrywk",
            "ترفيه", "سينما", "ألعاب", "娱乐", "电影", "游戏", "娯楽", "映画", "ゲーム", "여가", "영화", "게임", "გართობა", "კინო", "თამაშ"
        ],
        "Здоровье": [
            "здоров", "аптек", "врач", "лекарств", "health", "pharmac", "doctor", "medic", "առողջ", "դեղատուն", "բժիշկ", "դեղ",
            "лікар", "ліки", "salud", "farmacia", "médico", "medicina", "santé", "pharmacie", "médecin", "médicament", "gesundheit", "apotheke",
            "arzt", "medikament", "salute", "medico", "saúde", "farmácia", "remédio", "sağlık", "eczane", "doktor", "ilaç", "zdrowie", "apteka", "lekarz",
            "صحة", "صيدلية", "طبيب", "دواء", "医疗", "药店", "医生", "医療", "薬局", "病院", "건강", "약국", "병원", "의사", "ჯანმრთელობ", "აფთიაქ", "ექიმი"
        ],
        "Переводы": [
            "перевод", "transfer", "փոխանցում",
            "переказ", "transferencia", "virement", "überweisung", "ueberweisung", "bonifico", "trasferimento", "transferência", "havale", "przelew",
            "تحويل", "转账", "振込", "送金", "송금", "이체", "გადარიცხვა"
        ],
        "Прочее": ["прочее", "прочие", "other", "misc", "այլ"]
    ]

    private static func category(in text: String, financeService: FinanceService) -> Category? {
        let expenses = financeService.categories.filter { $0.type == .expense }
        for category in expenses {
            if let words = categoryWords[category.name], containsAny(text, words) {
                return category
            }
        }
        // Свои категории узнаём по началу названия
        return expenses.first { category in
            let stem = String(category.name.lowercased().prefix(5))
            return stem.count >= 4 && text.contains(stem)
        }
    }

    // MARK: - Ответы

    private static func expenses(in period: TimePeriodFilter, financeService: FinanceService) -> [Transaction] {
        financeService.transactions.filter { $0.type == .expense && period.contains($0.date) }
    }

    private static func format(_ amount: Double) -> String {
        CurrencyManager.shared.format(amount)
    }

    private static func categoryAnswer(_ category: Category, period: TimePeriodFilter, financeService: FinanceService) -> String {
        let items = expenses(in: period, financeService: financeService).filter { $0.category.name == category.name }
        let label = phrase(for: period)
        guard !items.isEmpty else {
            return String(localized: "\(label): трат в категории «\(category.displayName)» нет.")
        }
        let total = items.reduce(0.0) { $0 + $1.amount }
        var answer = String(localized: "\(label): на «\(category.displayName)» ушло \(format(total)) — операций: \(items.count).")

        var byMerchant: [String: Int] = [:]
        for item in items {
            byMerchant[item.brandName ?? item.title, default: 0] += 1
        }
        if let top = byMerchant.max(by: { $0.value < $1.value }), top.value > 1 {
            answer += " " + String(localized: "Чаще всего: \(top.key) (\(top.value)).")
        }
        return answer
    }

    private static func spendingAnswer(period: TimePeriodFilter, financeService: FinanceService) -> String {
        let items = expenses(in: period, financeService: financeService)
        let label = phrase(for: period)
        guard !items.isEmpty else {
            return String(localized: "\(label): трат нет.")
        }
        let total = items.reduce(0.0) { $0 + $1.amount }
        var answer = String(localized: "\(label): потрачено \(format(total)).")

        var byCategory: [String: Double] = [:]
        for item in items {
            byCategory[item.category.name, default: 0.0] += item.amount
        }
        let top = byCategory.sorted { $0.value > $1.value }.prefix(3)
        answer += "\n" + String(localized: "Больше всего:")
        for entry in top {
            answer += "\n• \(Category.displayName(for: entry.key)) — \(format(entry.value))"
        }

        let days: Double
        switch period {
        case .today: days = 1
        case .week: days = 7
        case .month: days = 30
        case .allTime: days = 0
        }
        if days > 1 {
            answer += "\n" + String(localized: "В среднем \(format(total / days)) в день.")
        }
        return answer
    }

    private static func incomeAnswer(period: TimePeriodFilter, financeService: FinanceService) -> String {
        let items = financeService.transactions.filter { $0.type == .income && period.contains($0.date) }
        let label = phrase(for: period)
        guard !items.isEmpty else {
            return String(localized: "\(label): поступлений нет.")
        }
        let total = items.reduce(0.0) { $0 + $1.amount }
        return String(localized: "\(label): получено \(format(total)) — поступлений: \(items.count).")
    }

    private static func subscriptionsAnswer(_ financeService: FinanceService) -> String {
        let active = financeService.subscriptions.filter(\.isActive)
        guard !active.isEmpty else {
            return String(localized: "Активных подписок нет. Добавьте первую в разделе «Долги» → «Подписки».")
        }
        let base = CurrencyManager.shared.baseCurrency
        func monthly(_ subscription: AppSubscription) -> Double {
            CurrencyService.shared.convert(amount: subscription.costPerMonth, from: subscription.currency, to: base)
        }
        let totals = SubscriptionTotals(financeService.subscriptions) { amount, currency in
            CurrencyService.shared.convert(amount: amount, from: currency, to: base)
        }
        var answer = String(localized: "Активных подписок: \(totals.count). В среднем \(format(totals.perMonth)) в месяц, \(format(totals.perYear)) в год.")
        for subscription in active.sorted(by: { monthly($0) > monthly($1) }).prefix(5) {
            answer += "\n• \(subscription.name) — \(subscription.currency.formatAmount(subscription.amount)) · \(subscription.period.repeatRule.title(every: subscription.effectiveInterval))"
        }
        return answer
    }

    private static func goalsAnswer(_ financeService: FinanceService) -> String {
        let goals = financeService.goals
        guard !goals.isEmpty else {
            return String(localized: "Копилок пока нет. Создайте первую в разделе «Обзор» → «Копилки».")
        }
        let summary = SavingsSummary(goals: goals)
        let saved = format(summary.totalSaved)
        var answer = String(localized: "Отложено \(saved). Активных копилок: \(summary.activeCount), достигнуто: \(summary.completedCount).")
        for goal in SavingsSummary.sortedActive(goals).prefix(5) {
            let plan = GoalPlan(goal: goal)
            answer += "\n• \(goal.title): \(GoalText.percent(plan))% (\(format(plan.saved)) / \(format(plan.target))) — \(GoalText.statusTitle(plan.status))"
        }
        return answer
    }

    private static func balanceAnswer(_ financeService: FinanceService) -> String {
        let cards = financeService.cards
        let cash = financeService.cashBalance
        let hasCash = abs(cash) > 0.005
        guard !cards.isEmpty || hasCash else {
            return String(localized: "Карт пока нет. Пришлите скриншот СМС банка — карта добавится сама, а баланс возьмётся из остатка.")
        }
        var answer = ""
        if !cards.isEmpty {
            answer = String(localized: "На картах \(format(financeService.cardsBalance)):")
            for card in cards {
                let frozen = card.isFrozen ? " " + String(localized: "(заморожена, не считается)") : ""
                answer += "\n• •••• \(card.last4) — \(format(card.balance))\(frozen)"
            }
        }
        if hasCash {
            if !answer.isEmpty {
                answer += "\n"
            }
            answer += String(localized: "Наличные") + ": " + format(cash)
            if !cards.isEmpty {
                answer += "\n" + String(localized: "Всего: \(format(financeService.totalBalance))")
            }
        }
        return answer
    }

    private static func debtsAnswer(_ financeService: FinanceService) -> String {
        // Платежи (коммуналка, интернет) считаются отдельно: это не долги людям и не кредиты
        let open = financeService.debts.filter { !$0.isPaid && $0.type != .bill }
        let bills = financeService.debts.filter { !$0.isPaid && $0.type == .bill }
        guard !open.isEmpty || !bills.isEmpty else {
            return String(localized: "Открытых долгов нет.")
        }

        var lines: [String] = []
        if !open.isEmpty {
            let lent = open.filter(\.isLent)
            let borrowed = open.filter { !$0.isLent }
            let owedToMe = format(lent.reduce(0.0) { $0 + $1.amount })
            let iOwe = format(borrowed.reduce(0.0) { $0 + $1.amount })
            lines.append(String(localized: "Мне должны: \(owedToMe). Я должен: \(iOwe)."))

            if let nearest = open.min(by: { $0.dueDate < $1.dueDate }) {
                let date = nearest.dueDate.formatted(.dateTime.day().month(.wide))
                let amount = format(nearest.amount)
                if nearest.isLent {
                    lines.append(String(localized: "Ближайший срок: \(date) — \(nearest.name) должен вам \(amount)."))
                } else {
                    lines.append(String(localized: "Ближайший срок: \(date) — вы должны \(nearest.name): \(amount)."))
                }
            }
        }
        if let nextBill = bills.min(by: { $0.dueDate < $1.dueDate }) {
            let total = format(bills.reduce(0.0) { $0 + $1.amount })
            let date = nextBill.dueDate.formatted(.dateTime.day().month(.wide))
            lines.append(String(localized: "Платежи к оплате: \(bills.count) на \(total). Ближайший: \(nextBill.name), \(date) — \(format(nextBill.amount))."))
        }
        return lines.joined(separator: "\n")
    }

    private static func adviceAnswer(_ financeService: FinanceService) -> String {
        AIService.shared.generateInsights(financeService: financeService)
            .map { "• \($0.title). \($0.message)" }
            .joined(separator: "\n")
    }
}
