import SwiftUI
import NDKSwift

@main
struct TENEXApp: App {
    @State private var nostrManager = NostrManager()
    
    init() {
        // Enable NDK network traffic logging
        NDKLogger.logNetworkTraffic = true
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(nostrManager)
        }
    }
}
