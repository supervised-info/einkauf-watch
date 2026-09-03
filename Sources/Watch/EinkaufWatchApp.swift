import SwiftUI

@main
struct EinkaufWatchApp: App {
    @StateObject private var store = ShoppingStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRoot()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.reloadFromPersistenceIfNewer()
            WatchComplicationReload.timelines()
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
