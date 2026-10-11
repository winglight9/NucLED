import Foundation

/// Looks up strings from the Swift package's localized resources.
/// Bundle.module selects the best match for the macOS preferred languages and
/// falls back to the package's declared default localization (Simplified Chinese).
enum AppText {
    static func localized(_ key: String, _ arguments: CVarArg...) -> String {
        let format = Bundle.module.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.autoupdatingCurrent, arguments: arguments)
    }
}
