import SwiftUI

@main
struct EinkaufWatchApp: App {
    @StateObject private var store = ShoppingStore()

    var body: some Scene {
        WindowGroup {
            WatchListView()
                .environmentObject(store)
        }
    }
}
