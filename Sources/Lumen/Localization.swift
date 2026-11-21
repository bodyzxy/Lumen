import Foundation
import SwiftUI

/// 界面语言：中文 / English
enum AppLanguage: String, CaseIterable, Identifiable {
    case zh, en
    var id: String { rawValue }
    var displayName: String { self == .zh ? "中文" : "English" }
}

/// 当前语言。界面里所有文字都通过 L(中文, 英文) 取值；
/// 切换语言时整个界面会重新生成，所以不需要逐个视图去监听。
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    private static let key = "lumen.language"

    /// 供 L() 快速读取
    private(set) static var current: AppLanguage = LanguageSettings.initial()

    @Published var language: AppLanguage {
        didSet {
            LanguageSettings.current = language
            UserDefaults.standard.set(language.rawValue, forKey: LanguageSettings.key)
        }
    }

    private init() {
        language = LanguageSettings.current
    }

    /// 第一次启动时跟随系统语言：系统是中文就用中文，否则用英文
    private static func initial() -> AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: key), let lang = AppLanguage(rawValue: saved) {
            return lang
        }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("zh") ? .zh : .en
    }
}

/// 按当前语言返回文字
@inline(__always)
func L(_ zh: String, _ en: String) -> String {
    LanguageSettings.current == .en ? en : zh
}
