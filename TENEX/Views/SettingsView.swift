import SwiftUI
import NDKSwift

struct SettingsView: View {
    @Environment(NostrManager.self) var nostrManager
    @AppStorage("openRouterAPIKey") private var openRouterAPIKey = ""
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @State private var showingLogoutAlert = false
    @State private var showingWipeDataAlert = false
    @State private var isWipingData = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let user = nostrManager.currentUser {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Public Key")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(user.npub.prefix(16) + "...")
                                    .font(.system(.body, design: .monospaced))
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                UIPasteboard.general.string = user.npub
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    Button("Logout") {
                        showingLogoutAlert = true
                    }
                    .foregroundColor(.red)
                }
                
                Section("API Keys") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OpenRouter API Key")
                            .font(.caption)
                            .foregroundColor(.gray)
                        SecureField("Enter your API key", text: $openRouterAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OpenAI API Key")
                            .font(.caption)
                            .foregroundColor(.gray)
                        SecureField("Enter your API key", text: $openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .listRowSeparator(.hidden)
                
                Section {
                    Link(destination: URL(string: "https://openrouter.ai/keys")!) {
                        HStack {
                            Text("Get OpenRouter API Key")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                        HStack {
                            Text("Get OpenAI API Key")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section("Relays") {
                    NavigationLink(destination: RelayManagementView()) {
                        HStack {
                            Label("Manage Relays", systemImage: "network")
                            Spacer()
                            Text("\(RelayManager.shared.relays.count)")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                }
                
                #if DEBUG
                Section("Debug") {
                    Button("Wipe Cache Database") {
                        showingWipeDataAlert = true
                    }
                    .foregroundColor(.red)
                    .disabled(isWipingData)
                    
                    if isWipingData {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Wiping database...")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .alert("Logout", isPresented: $showingLogoutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    nostrManager.logout()
                }
            } message: {
                Text("Are you sure you want to logout?")
            }
            .alert("Wipe Database", isPresented: $showingWipeDataAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Wipe", role: .destructive) {
                    Task {
                        await wipeDatabase()
                    }
                }
            } message: {
                Text("Are you sure you want to wipe the cache database? This will clear all cached Nostr events and require re-syncing from relays.")
            }
        }
    }
    
    @MainActor
    private func wipeDatabase() async {
        isWipingData = true
        defer { isWipingData = false }
        
        do {
            if let cache = nostrManager.cache {
                try await cache.clear()
                print("Successfully wiped cache database")
            } else {
                print("No cache instance available to wipe")
            }
        } catch {
            print("Failed to wipe cache database: \(error)")
        }
    }
}