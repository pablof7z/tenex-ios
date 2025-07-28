import SwiftUI

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
    }
}