import Foundation

enum LanguagePreference: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
}

@MainActor
final class AppLanguage: ObservableObject {
    private static let defaultsKey = "app.language"

    @Published var preference: LanguagePreference {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: Self.defaultsKey)
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
        preference = saved.flatMap(LanguagePreference.init(rawValue:)) ?? .system
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
        case .system: "language.system"
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
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
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
