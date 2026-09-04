import SwiftUI

@main
struct EinkaufApp: App {
    @StateObject private var store = ShoppingStore()
    @StateObject private var todos = TodoStore()
    @StateObject private var appearance = AppearanceSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            EinkaufRoot()
                .environmentObject(store)
                .environmentObject(todos)
                .environmentObject(appearance)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.reloadFromPersistenceIfNewer()
            todos.reloadFromPersistenceIfNewer()
            HomeWidgetReload.timelines()
        }
    }
}

struct EinkaufRoot: View {
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let theme = appearance.tokens(system: systemScheme)
        TabView {
            ContentView()
                .tabItem {
                    Label("Einkauf", systemImage: "basket")
                }
            TodoListView()
                .tabItem {
                    Label("To-Do", systemImage: "checklist")
                }
        }
        .environment(\.einkaufTheme, theme)
        .preferredColorScheme(appearance.preferredColorScheme)
        .einkaufScreen(theme)
#if os(iOS)
        .toolbarBackground(theme.paper2, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(theme.isDark ? .dark : .light, for: .tabBar)
#endif
    }
}

#Preview {
    EinkaufRoot()
        .environmentObject(ShoppingStore(state: .seed, enableSync: false))
        .environmentObject(TodoStore(state: .empty, enableSync: false))
        .environmentObject(AppearanceSettings())
}
