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

private enum RootTab: Hashable {
    case einkauf
    case todo
}

struct EinkaufRoot: View {
    @EnvironmentObject private var store: ShoppingStore
    @EnvironmentObject private var todos: TodoStore
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.colorScheme) private var systemScheme
    @State private var selectedTab: RootTab = .einkauf
    @State private var urlAlert: String?
    @State private var pendingTodoData: Data?
    @State private var showTodoImportChoice = false
    @State private var todoImportSummary = ""

    var body: some View {
        let theme = appearance.tokens(system: systemScheme)
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    Label("Einkauf", systemImage: "basket")
                }
                .tag(RootTab.einkauf)
            TodoListView()
                .tabItem {
                    Label("To-Do", systemImage: "checklist")
                }
                .tag(RootTab.todo)
        }
        .environment(\.einkaufTheme, theme)
        .preferredColorScheme(appearance.preferredColorScheme)
        .einkaufScreen(theme)
#if os(iOS)
        .toolbarBackground(theme.paper2, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(theme.isDark ? .dark : .light, for: .tabBar)
        .onOpenURL { url in
            handleOpenURL(url)
        }
        .alert("Hinweis", isPresented: Binding(get: { urlAlert != nil }, set: { if !$0 { urlAlert = nil } })) {
            Button("OK", role: .cancel) { urlAlert = nil }
        } message: {
            Text(urlAlert ?? "")
        }
        .confirmationDialog("To-Do importieren", isPresented: $showTodoImportChoice, titleVisibility: .visible) {
            Button("Anhängen") { commitPendingTodo(append: true) }
            Button("Ersetzen") { commitPendingTodo(append: false) }
            Button("Abbrechen", role: .cancel) { pendingTodoData = nil }
        } message: {
            Text(todoImportSummary)
        }
#endif
    }

#if os(iOS)
    private func handleOpenURL(_ url: URL) {
        if url.scheme == "einkauf" {
            selectedTab = url.host == "todo" ? .todo : .einkauf
            return
        }
        do {
            let data = try IncomingJSON.data(from: url)
            switch IncomingJSON.classify(data) {
            case .todoBackup:
                try offerOrApplyTodo(data)
            case .einkaufBackup:
                try store.importBackup(data)
                selectedTab = .einkauf
            case .invalidJSON:
                try offerOrApplyTodo(data)
            case .unknown:
                urlAlert = IncomingJSONError.unknownFormat.localizedDescription
            }
        } catch {
            urlAlert = error.localizedDescription
        }
    }

    private func offerOrApplyTodo(_ data: Data) throws {
        let incoming = try TodoImport.decode(data)
        selectedTab = .todo
        if todos.state.tasks.isEmpty {
            try todos.importAny(data, append: false)
            return
        }
        pendingTodoData = data
        todoImportSummary = TodoImportPrompt.message(
            currentCount: todos.state.tasks.count,
            incomingCount: incoming.tasks.count
        )
        showTodoImportChoice = true
    }

    private func commitPendingTodo(append: Bool) {
        guard let data = pendingTodoData else { return }
        pendingTodoData = nil
        do {
            try todos.importAny(data, append: append)
            selectedTab = .todo
        } catch {
            urlAlert = error.localizedDescription
        }
    }
#endif
}

#Preview {
    EinkaufRoot()
        .environmentObject(ShoppingStore(state: .seed, enableSync: false))
        .environmentObject(TodoStore(state: .empty, enableSync: false))
        .environmentObject(AppearanceSettings())
}
