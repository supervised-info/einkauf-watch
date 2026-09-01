import SwiftUI

@main
struct EinkaufWatchApp: App {
    @StateObject private var store = ShoppingStore()

    var body: some Scene {
        WindowGroup {
            WatchRoot()
                .environmentObject(store)
        }
    }
}

private struct WatchRoot: View {
    @EnvironmentObject private var store: ShoppingStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = ThemeTokens.make(palette: .vintage, scheme: scheme)
        WatchListView()
            .environment(\.einkaufTheme, theme)
            .tint(theme.oxide)
    }
}
