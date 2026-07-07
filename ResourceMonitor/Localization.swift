import Foundation
import SwiftUI
import Combine

// MARK: - Language selection

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, en, nl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L("System")
        case .en:     return "English"
        case .nl:     return "Nederlands"
        }
    }

    /// Explicit language code, or nil to follow the system.
    var code: String? {
        switch self {
        case .system: return nil
        case .en:     return "en"
        case .nl:     return "nl"
        }
    }
}

/// Resolve a localized string against the (possibly overridden) main bundle.
/// Use for strings shown via `Text(String)` where SwiftUI would otherwise treat
/// the value verbatim — e.g. enum labels and computed titles.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

// MARK: - Bundle swizzle for runtime language override

private var localizedBundleKey: UInt8 = 0

/// Subclass whose `localizedString(forKey:…)` is redirected to a chosen `.lproj`
/// bundle. Installing this class onto `Bundle.main` lets SwiftUI `Text("…")` and
/// `NSLocalizedString` resolve against the selected language without an app restart.
private final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let override = objc_getAssociatedObject(self, &localizedBundleKey) as? Bundle {
            return override.localizedString(forKey: key, value: value, table: tableName)
        }
        // No override means English. The source language *is* the key, so return
        // it directly. We must NOT call super here: the only compiled strings
        // table in the bundle is nl.lproj, so super would resolve to Dutch.
        return value?.isEmpty == false ? value! : key
    }
}

extension Bundle {
    /// Redirect `Bundle.main` string lookups to the `.lproj` for `code`.
    /// Pass `"en"`/`nil` to render the source (English) strings.
    static func setLanguage(_ code: String?) {
        // Install the subclass once; object_setClass is idempotent here.
        object_setClass(Bundle.main, LocalizedBundle.self)

        // English (or unknown) uses the source keys, so no override bundle.
        let override: Bundle?
        if let code, code != "en",
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let b = Bundle(path: path) {
            override = b
        } else {
            override = nil
        }
        objc_setAssociatedObject(Bundle.main, &localizedBundleKey, override,
                                 .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - Localization manager

/// Observable source of truth for the active language. Views observe this so a
/// language change forces a rebuild; `localeIdentifier` drives number/date formatting.
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var language: AppLanguage = .system

    private init() {}

    /// Resolved locale for the active language (used for `.environment(\.locale, …)`).
    var locale: Locale {
        Locale(identifier: resolvedCode)
    }

    /// Stable token that changes with the language — attach via `.id(...)` to force rebuilds.
    var token: String { language.rawValue }

    private var resolvedCode: String {
        if let code = language.code { return code }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return String(preferred.prefix(2))
    }

    func apply(_ language: AppLanguage) {
        self.language = language

        // Safety net for the native localization path (used after relaunch or if
        // SwiftUI resolves a Text without hitting the bundle swizzle): pin the
        // Foundation-level language for an explicit choice, clear it for system.
        let defaults = UserDefaults.standard
        if let code = language.code {
            defaults.set([code], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }

        // For `.system` this resolves to the actual system language (en/nl).
        Bundle.setLanguage(resolvedCode)
        objectWillChange.send()
    }
}

// MARK: - View helper

extension View {
    /// Applies the active language's locale and rebuilds when it changes.
    /// Attach to every independent hosting-controller root.
    func localized(_ manager: LocalizationManager = .shared) -> some View {
        modifier(LocalizedRoot(manager: manager))
    }
}

private struct LocalizedRoot: ViewModifier {
    @ObservedObject var manager: LocalizationManager

    func body(content: Content) -> some View {
        content
            .environment(\.locale, manager.locale)
            .id(manager.token)
    }
}
