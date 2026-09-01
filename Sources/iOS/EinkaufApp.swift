import SwiftUI

@main
struct EinkaufApp: App {
    @StateObject private var store = ShoppingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
