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
        // Get connected relays from NDK
        relays = Array(nostrManager.ndk.relayPool.connectedRelays().map { $0.url })
    }
    
    private func addRelay(_ url: String) {
        Task {
            await nostrManager.ndk.relayPool.addRelay(url)
            loadRelays()
        }
    }
    
    private func removeRelay(_ url: String) {
        Task {
            if let relay = nostrManager.ndk.relayPool.relay(url) {
                await nostrManager.ndk.relayPool.removeRelay(relay)
                loadRelays()
            }
        }
    }
}