import SwiftUI
import NDKSwift

struct RelayManagementView: View {
    @Environment(NostrManager.self) var nostrManager
    @State private var relays: [String] = []
    @State private var newRelayURL = ""
    @State private var showingAddRelay = false
    
    var body: some View {
        List {
            ForEach(relays, id: \.self) { relay in
                HStack {
                    Text(relay)
                    Spacer()
                    Button("Remove") {
                        removeRelay(relay)
                    }
                    .foregroundColor(.red)
                }
            }
            
            Button("Add Relay") {
                showingAddRelay = true
            }
        }
        .navigationTitle("Relays")
        .sheet(isPresented: $showingAddRelay) {
            NavigationStack {
                VStack {
                    TextField("Relay URL", text: $newRelayURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                    
                    Button("Add") {
                        if !newRelayURL.isEmpty {
                            addRelay(newRelayURL)
                            newRelayURL = ""
                            showingAddRelay = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                }
                .navigationTitle("Add Relay")
                .navigationBarItems(trailing: Button("Cancel") {
                    showingAddRelay = false
                })
            }
        }
        .onAppear {
            loadRelays()
        }
    }
    
    private func loadRelays() {
        Task {
            // Get all relays from NDK and filter connected ones
            let allRelays = await nostrManager.ndk.relays
            var connectedRelayUrls: [String] = []
            
            for relay in allRelays {
                let state = await relay.connectionState
                if state == .connected {
                    connectedRelayUrls.append(relay.url)
                }
            }
            
            await MainActor.run {
                relays = connectedRelayUrls
            }
        }
    }
    
    private func addRelay(_ url: String) {
        Task {
            await nostrManager.ndk.addRelay(url)
            loadRelays()
        }
    }
    
    private func removeRelay(_ url: String) {
        Task {
            await nostrManager.ndk.removeRelay(url)
            loadRelays()
        }
    }
}