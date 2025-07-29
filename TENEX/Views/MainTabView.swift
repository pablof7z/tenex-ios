import SwiftUI
import NDKSwift

struct MainTabView: View {
    @Environment(NostrManager.self) var nostrManager
    
    var body: some View {
        TabView {
            ProjectListView()
                .tabItem {
                    Label("Chats", systemImage: "message.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .task {
            // Start monitoring projects and status when the main view loads
            if let pubkey = NDKAuthManager.shared.activePubkey {
                let user = NDKUser(pubkey: pubkey)
                await nostrManager.startStatusMonitoring(for: user)
            }
        }
    }
}