import SwiftUI

@main
struct EinkaufApp: App {
    @StateObject private var store = ShoppingStore()
    @StateObject private var appearance = AppearanceSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            EinkaufRoot()
                .environmentObject(store)
                .environmentObject(appearance)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            HomeWidgetReload.timelines()
        }
    }
}

struct EinkaufRoot: View {
    @EnvironmentObject private var store: ShoppingStore
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let theme = appearance.tokens(system: systemScheme)
        ContentView()
            .environment(\.einkaufTheme, theme)
            .preferredColorScheme(appearance.preferredColorScheme)
            .einkaufScreen(theme)
    }
}

#Preview {
    EinkaufRoot()
        .environmentObject(ShoppingStore(state: .seed, enableSync: false))
        .environmentObject(AppearanceSettings())
}
