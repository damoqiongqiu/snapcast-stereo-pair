import Foundation
import XCTest
@testable import MacStereoPair

@MainActor
final class AppLanguageTests: XCTestCase {
    func testFreshInstallDefaultsToEnglish() {
        withDefaults { defaults in
            let language = AppLanguage(defaults: defaults)

            XCTAssertEqual(language.preference, .english)
            XCTAssertEqual(language.locale.identifier, "en")
        }
    }

    func testSavedLanguageOverridesEnglishDefault() {
        withDefaults { defaults in
            defaults.set(LanguagePreference.simplifiedChinese.rawValue, forKey: "app.language")

            let language = AppLanguage(defaults: defaults)

            XCTAssertEqual(language.preference, .simplifiedChinese)
            XCTAssertEqual(language.locale.identifier, "zh-Hans")
        }
    }

    func testUnknownSavedPreferenceFallsBackToEnglish() {
        withDefaults { defaults in
            defaults.set("unsupported", forKey: "app.language")

            let language = AppLanguage(defaults: defaults)

            XCTAssertEqual(language.preference, .english)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        body(defaults)
    }
}
