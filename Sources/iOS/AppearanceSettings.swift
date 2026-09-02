import SwiftUI

/// Hell/Dunkel/System und Creme/Blau. Native UserDefaults (`einkauf.theme` / `einkauf.palette`).
@MainActor
final class AppearanceSettings: ObservableObject {
    static let themeKey = "einkauf.theme"
    static let paletteKey = "einkauf.palette"

    private let defaults: UserDefaults

    @Published var theme: AppThemePreference {
        didSet { persist() }
    }

    @Published var palette: AppPalette {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = AppThemePreference.parse(defaults.string(forKey: Self.themeKey))
        palette = defaults.string(forKey: Self.paletteKey) == AppPalette.navy.rawValue ? .navy : .vintage
    }

    var preferredColorScheme: ColorScheme? {
        theme.preferredColorScheme
    }

    func tokens(system: ColorScheme) -> ThemeTokens {
        let scheme = preferredColorScheme ?? system
        return ThemeTokens.make(palette: palette, scheme: scheme)
    }

    private func persist() {
        defaults.set(theme.rawValue, forKey: Self.themeKey)
        defaults.set(palette.rawValue, forKey: Self.paletteKey)
    }
}
