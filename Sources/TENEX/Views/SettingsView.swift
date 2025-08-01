import SwiftUI
import NDKSwift

struct SettingsView: View {
    @Environment(NostrManager.self) var nostrManager
    @AppStorage("openRouterAPIKey") private var openRouterAPIKey = ""
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @State private var showingLogoutAlert = false
    @State private var showingWipeDataAlert = false
    @State private var isWipingData = false
    @State private var currentUserNpub: String?
    @State private var relayCount = 0
    
    var body: some View {
        NavigationStack {
            Form {
                accountSection
                apiKeysSection
                relaysSection
                aboutSection
                #if DEBUG
                debugSection
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
    
    private var accountSection: some View {
        Section("Account") {
            if nostrManager.hasActiveUser {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Public Key")
                            .font(.caption)
                            .foregroundColor(.gray)
                        if let npub = currentUserNpub {
                            Text(String(npub.prefix(16)) + "...")
                                .font(.system(.body, design: .monospaced))
                        } else {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        if let npub = currentUserNpub {
                            UIPasteboard.general.string = npub
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.blue)
                    }
                    .disabled(currentUserNpub == nil)
                }
                .task {
                    if let user = await nostrManager.currentUser {
                        currentUserNpub = user.npub
                    }
                }
            }
            
            Button("Logout") {
                showingLogoutAlert = true
            }
            .foregroundColor(.red)
        }
    }
    
    private var apiKeysSection: some View {
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
    }
    
    private var relaysSection: some View {
        Section("Relays") {
            NavigationLink(destination: RelayManagementView()) {
                HStack {
                    Text("Manage Relays")
                    Spacer()
                    if relayCount > 0 {
                        Text("\(relayCount)")
                            .foregroundColor(.gray)
                    }
                }
            }
            .task {
                let relays = await nostrManager.ndk.relays
                relayCount = relays.count
            }
        }
    }
    
    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.gray)
            }
        }
    }
    
    #if DEBUG
    private var debugSection: some View {
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
    }
    #endif
    
    @MainActor
    private func wipeDatabase() async {
        isWipingData = true
        defer { isWipingData = false }
        
        do {
            try await nostrManager.clearCache()
            print("Successfully wiped cache database")
        } catch {
            print("Failed to wipe cache database: \(error)")
        }
    }
}