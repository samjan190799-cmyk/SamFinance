import Foundation

/// Языки интерфейса. Язык выбирает iOS: по языку телефона или отдельно для приложения
/// (Настройки → Hashiv → Язык). Строки лежат в Localizable.strings: ключ — русский текст,
/// для русского языка перевод не нужен, для английского и армянского есть файлы en.lproj и hy.lproj.
public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case russian = "ru"
    case english = "en"
    case armenian = "hy"

    public var id: String { rawValue }

    /// Название языка на нём самом
    public var displayName: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        case .armenian: return "Հայերեն"
        }
    }

    /// Название для подсказки ИИ: на каком языке отвечать
    var promptName: String {
        switch self {
        case .russian: return "русский"
        case .english: return "английский (English)"
        case .armenian: return "армянский (հայերեն)"
        }
    }

    /// Язык, на котором приложение показано сейчас. Если язык телефона не поддерживается, берётся английский.
    public static var current: AppLanguage {
        for code in Bundle.main.preferredLocalizations {
            if let language = AppLanguage(code: code) {
                return language
            }
        }
        return .english
    }

    /// Язык, который выбрал пользователь: он вступит в силу после перезапуска. Пока выбора не было, это текущий язык.
    public static var selected: AppLanguage {
        if let codes = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
           let first = codes.first,
           let language = AppLanguage(code: first) {
            return language
        }
        return current
    }

    private init?(code: String) {
        let base = code.split(separator: "-").first.map(String.init) ?? code
        self.init(rawValue: base)
    }

    /// Запоминает выбор языка. iOS не показывает армянский в списке языков телефона, поэтому выбор хранится в AppleLanguages
    /// приложения; перевод всех строк, дат и системных элементов меняется при следующем запуске.
    public static func select(_ language: AppLanguage) {
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }

    /// Строка на этом языке независимо от текущего (нужна, чтобы объяснить смену языка на самом новом языке)
    public func string(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

public extension String {
    /// Перевод по ключу из Localizable.strings; если ключа нет, возвращается сам ключ
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
}
