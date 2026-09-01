import SwiftUI

/// Hell/Dunkel und Creme/Blau, analog `supervised-info.theme` / `.palette`. Native UserDefaults.
@MainActor
final class AppearanceSettings: ObservableObject {
    static let themeKey = "einkauf.theme"
    static let paletteKey = "einkauf.palette"

    private let defaults: UserDefaults

    /// `nil` = System folgen (Default).
    @Published var themeOverride: AppColorMode? {
        didSet { persist() }
    }

    @Published var palette: AppPalette {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        switch defaults.string(forKey: Self.themeKey) {
        case AppColorMode.light.rawValue:
            themeOverride = .light
        case AppColorMode.dark.rawValue:
            themeOverride = .dark
        default:
            themeOverride = nil
        }
        palette = defaults.string(forKey: Self.paletteKey) == AppPalette.navy.rawValue ? .navy : .vintage
    }

    var preferredColorScheme: ColorScheme? {
        switch themeOverride {
        case .light: return .light
        case .dark: return .dark
        case nil: return nil
        }
    }

    func resolvedMode(system: ColorScheme) -> AppColorMode {
        themeOverride ?? (system == .dark ? .dark : .light)
    }

    func tokens(system: ColorScheme) -> ThemeTokens {
        let scheme = preferredColorScheme ?? system
        return ThemeTokens.make(palette: palette, scheme: scheme)
    }

    private func persist() {
        if let themeOverride {
            defaults.set(themeOverride.rawValue, forKey: Self.themeKey)
        } else {
            defaults.removeObject(forKey: Self.themeKey)
        }
        defaults.set(palette.rawValue, forKey: Self.paletteKey)
    }
}
