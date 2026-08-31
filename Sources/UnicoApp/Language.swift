import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"
    var id: String { rawValue }
    var name: String { self == .chinese ? "简体中文" : "English" }
    var locale: Locale { Locale(identifier: self == .chinese ? "zh_CN" : "en_US") }
    static func initial(defaults: UserDefaults = .standard) -> Self {
        if let value = defaults.string(forKey: "Unico.language"), let saved = Self(rawValue: value) { return saved }
        return .english
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
