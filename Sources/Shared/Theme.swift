import SwiftUI

enum AppPalette: String, CaseIterable, Identifiable, Sendable {
    case vintage
    case navy
    var id: String { rawValue }
}

enum AppColorMode: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark
    var id: String { rawValue }
}

/// supervised-info Vintage- und Navy-Tokens (HTML `:root` / `data-theme` / `data-palette`).
struct ThemeRGB: Equatable, Sendable {
    var paper: UInt32
    var paper2: UInt32
    var paper3: UInt32
    var ink: UInt32
    var muted: UInt32
    var rule: UInt32
    var oxide: UInt32
    var good: UInt32

    static func tokens(palette: AppPalette, dark: Bool) -> ThemeRGB {
        switch (palette, dark) {
        case (.vintage, false):
            return ThemeRGB(
                paper: 0xF3EEE4,
                paper2: 0xE9E1D2,
                paper3: 0xDFD5C4,
                ink: 0x1C1814,
                muted: 0x5E564D,
                rule: 0xD2C8B8,
                oxide: 0x9C3424,
                good: 0x2C6A4A
            )
        case (.vintage, true):
            return ThemeRGB(
                paper: 0x14110E,
                paper2: 0x1D1915,
                paper3: 0x2A241D,
                ink: 0xF3EEE4,
                muted: 0xB3AA9C,
                rule: 0x3D362C,
                oxide: 0xE07060,
                good: 0x7DBA96
            )
        case (.navy, false):
            return ThemeRGB(
                paper: 0xF0F4FF,
                paper2: 0xFFFFFF,
                paper3: 0xE8ECF8,
                ink: 0x08102A,
                muted: 0x4A6080,
                rule: 0xBFCFE8,
                oxide: 0x2060DF,
                good: 0x059669
            )
        case (.navy, true):
            return ThemeRGB(
                paper: 0x060C1A,
                paper2: 0x0C1828,
                paper3: 0x102038,
                ink: 0xEDF2FF,
                muted: 0x6E8FB0,
                rule: 0x1B2F4A,
                oxide: 0x4A94FF,
                good: 0x34D399
            )
        }
    }
}

struct ThemeTokens: Equatable {
    var rgb: ThemeRGB
    var isDark: Bool

    var paper: Color { Color(rgb: rgb.paper) }
    var paper2: Color { Color(rgb: rgb.paper2) }
    var paper3: Color { Color(rgb: rgb.paper3) }
    var ink: Color { Color(rgb: rgb.ink) }
    var muted: Color { Color(rgb: rgb.muted) }
    var rule: Color { Color(rgb: rgb.rule) }
    var oxide: Color { Color(rgb: rgb.oxide) }
    var good: Color { Color(rgb: rgb.good) }

    static func make(palette: AppPalette, scheme: ColorScheme) -> ThemeTokens {
        ThemeTokens(rgb: .tokens(palette: palette, dark: scheme == .dark), isDark: scheme == .dark)
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

private struct EinkaufThemeKey: EnvironmentKey {
    static let defaultValue = ThemeTokens.make(palette: .vintage, scheme: .light)
}

extension EnvironmentValues {
    var einkaufTheme: ThemeTokens {
        get { self[EinkaufThemeKey.self] }
        set { self[EinkaufThemeKey.self] = newValue }
    }
}

struct EinkaufScreenModifier: ViewModifier {
    var theme: ThemeTokens

    func body(content: Content) -> some View {
        content
            .tint(theme.oxide)
            .background(theme.paper)
#if os(iOS)
            .toolbarBackground(theme.paper2, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
#endif
    }
}

struct EinkaufListModifier: ViewModifier {
    @Environment(\.einkaufTheme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.paper)
#if os(iOS)
            .listRowSeparatorTint(theme.rule)
#endif
    }
}

struct EinkaufRowModifier: ViewModifier {
    @Environment(\.einkaufTheme) private var theme

    func body(content: Content) -> some View {
        content
            .listRowBackground(theme.paper2)
#if os(iOS)
            .listRowSeparatorTint(theme.rule)
#endif
            .foregroundStyle(theme.ink)
    }
}

extension View {
    func einkaufScreen(_ theme: ThemeTokens) -> some View {
        modifier(EinkaufScreenModifier(theme: theme))
    }

    func einkaufListChrome() -> some View {
        modifier(EinkaufListModifier())
    }

    func einkaufRowChrome() -> some View {
        modifier(EinkaufRowModifier())
    }
}
