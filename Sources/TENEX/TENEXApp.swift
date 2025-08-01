import SwiftUI
import NDKSwift

@main
struct TENEXApp: App {
    @State private var nostrManager = NostrManager()
    
    init() {
        // Enable NDK network traffic logging
        NDKLogger.logNetworkTraffic = true
        NDKLogger.configure(
            logLevel: .trace,
            enabledCategories: [
                .subscription,
                .cache,
                .event,
                .outbox
            ],
            logNetworkTraffic: true
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(nostrManager)
        }
    }
}
