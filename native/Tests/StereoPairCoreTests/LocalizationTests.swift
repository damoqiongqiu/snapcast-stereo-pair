import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    func testEnglishAndSimplifiedChineseHaveMatchingNonEmptyKeys() throws {
        let english = try loadStrings(language: "en")
        let chinese = try loadStrings(language: "zh-Hans")

        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        XCTAssertFalse(english.isEmpty)
        XCTAssertTrue(english.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        XCTAssertTrue(chinese.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testRequiredLocalizationCategoriesAreCovered() throws {
        let strings = try loadStrings(language: "en")
        let requiredPrefixes = [
            "mode.",
            "service.",
            "volume.",
            "systemVolume.",
            "latency.",
            "error.",
            "setup.",
            "accessibility."
        ]

        for prefix in requiredPrefixes {
            XCTAssertTrue(
                strings.keys.contains { $0.hasPrefix(prefix) },
                "Missing localization category: \(prefix)"
            )
        }
    }

    private func loadStrings(language: String) throws -> [String: String] {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = sourceRoot
            .appendingPathComponent("Sources/MacStereoPair/Resources")
            .appendingPathComponent("\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let strings = propertyList as? [String: String] else {
            XCTFail("Localizable.strings is not a string dictionary: \(url.path)")
            return [:]
        }
        return strings
    }
}
