import Foundation

enum AppLanguage {
    case chinese
    case english
    var locale: Locale { Locale(identifier: self == .chinese ? "zh_CN" : "en_US") }
    static func system(defaults: UserDefaults = .standard) -> Self {
        let preferred = defaults.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        guard let primaryLanguage = preferred.first else { return .english }
        return usesSimplifiedChinese(primaryLanguage) ? .chinese : .english
    }

    /// Unico ships Simplified Chinese and English. Every other primary language,
    /// including Traditional Chinese, falls back to English until it is localized.
    private static func usesSimplifiedChinese(_ identifier: String) -> Bool {
        let normalized = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
        return normalized == "zh"
            || normalized.hasPrefix("zh-hans")
            || normalized.hasPrefix("zh-cn")
            || normalized.hasPrefix("zh-sg")
    }

    func text(_ chinese: String, _ english: String) -> String { self == .chinese ? chinese : english }
}

struct AppMessage {
    let chinese: String
    let english: String
    init(_ chinese: String, _ english: String) { self.chinese = chinese; self.english = english }
    func text(_ language: AppLanguage) -> String { language.text(chinese, english) }
}

func englishCount(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
    "\(count) " + (count == 1 ? singular : (plural ?? singular + "s"))
}
