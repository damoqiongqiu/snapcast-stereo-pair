import Foundation

enum LanguagePreference: String, CaseIterable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
}

@MainActor
final class AppLanguage: ObservableObject {
    private static let defaultsKey = "app.language"
    private let defaults: UserDefaults

    @Published var preference: LanguagePreference {
        didSet {
            defaults.set(preference.rawValue, forKey: Self.defaultsKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.defaultsKey)
        preference = saved.flatMap(LanguagePreference.init(rawValue:)) ?? .english
    }

    var locale: Locale {
        Locale(identifier: resolvedLanguageCode)
    }

    func text(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    func label(for preference: LanguagePreference) -> String {
        let key: String = switch preference {
        case .english: "language.english"
        case .simplifiedChinese: "language.chinese"
        }
        return text(key)
    }

    private var resolvedLanguageCode: String {
        switch preference {
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }

    private var localizedBundle: Bundle {
        guard let path = Bundle.module.path(forResource: resolvedLanguageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.module
        }
        return bundle
    }
}
