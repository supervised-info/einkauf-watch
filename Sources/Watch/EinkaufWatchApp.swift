import SwiftUI

@main
struct EinkaufWatchApp: App {
    @StateObject private var store = ShoppingStore()
    @StateObject private var todos = TodoStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRoot()
                .environmentObject(store)
                .environmentObject(todos)
                .task {
                    store.consumeSiriPendingAdds()
                    todos.consumeSiriPendingAdds()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.consumeSiriPendingAdds()
            todos.consumeSiriPendingAdds()
            store.reloadFromPersistenceIfNewer()
            todos.reloadFromPersistenceIfNewer()
            WatchComplicationReload.timelines()
            WatchComplicationReload.todoTimelines()
        }
    }
}

private enum WatchTab: Hashable {
    case einkauf
    case todo
}

private struct WatchRoot: View {
    @EnvironmentObject private var store: ShoppingStore
    @EnvironmentObject private var todos: TodoStore
    @Environment(\.colorScheme) private var scheme
    @State private var selectedTab: WatchTab = .einkauf

    var body: some View {
        let theme = ThemeTokens.make(palette: .vintage, scheme: scheme)
        TabView(selection: $selectedTab) {
            WatchListView()
                .tabItem {
                    Label("Einkauf", systemImage: "basket")
                }
                .tag(WatchTab.einkauf)
            WatchTodoListView()
                .tabItem {
                    Label("To-Do", systemImage: "checklist")
                }
                .tag(WatchTab.todo)
        }
        .environment(\.einkaufTheme, theme)
        .tint(theme.oxide)
        .onOpenURL { url in
            if url.scheme == "einkauf", url.host == "todo" {
                selectedTab = .todo
            } else if url.scheme == "einkauf" {
                selectedTab = .einkauf
            }
        }
    }
}
