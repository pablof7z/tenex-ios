import SwiftUI
import NDKSwift

struct RelayManagementView: View {
    @Environment(NostrManager.self) var nostrManager
    @StateObject private var relayManager = RelayManager.shared
    @State private var showingAddRelay = false
    @State private var newRelayURL = ""
    @State private var relayStatuses: [String: NDKRelayConnectionState] = [:]
    @State private var showingResetAlert = false
    
    var body: some View {
        List {
            Section {
                ForEach(relayManager.relays, id: \.self) { relayURL in
                    RelayRowView(
                        url: relayURL,
                        status: relayStatuses[relayURL] ?? .disconnected,
                        onDelete: {
                            relayManager.removeRelay(relayURL)
                            Task {
                                await updateRelayConnections()
                            }
                        }
                    )
                }
                .onDelete { offsets in
                    for index in offsets {
                        let relay = relayManager.relays[index]
                        relayManager.removeRelay(relay)
                    }
                    Task {
                        await updateRelayConnections()
                    }
                }
            } header: {
                Text("Active Relays")
            } footer: {
                Text("Swipe to remove relays")
                    .font(.caption)
            }
            
            Section {
                Button {
                    showingAddRelay = true
                } label: {
                    Label("Add Relay", systemImage: "plus.circle")
                }
                
                Button {
                    showingResetAlert = true
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .foregroundColor(.orange)
                }
            }
        }
        .navigationTitle("Relay Management")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Refresh") {
                    Task {
                        await refreshRelayStatuses()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddRelay) {
            AddRelayView(relayURL: $newRelayURL) {
                if !newRelayURL.isEmpty {
                    relayManager.addRelay(newRelayURL)
                    newRelayURL = ""
                    Task {
                        await updateRelayConnections()
                    }
                }
                showingAddRelay = false
            }
        }
        .alert("Reset Relays", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                relayManager.resetToDefaults()
                Task {
                    await updateRelayConnections()
                }
            }
        } message: {
            Text("This will reset your relay list to the default relays. Are you sure?")
        }
        .task {
            await refreshRelayStatuses()
        }
    }
    
    @MainActor
    private func refreshRelayStatuses() async {
        let ndk = nostrManager.ndk
        let relays = await ndk.relays
        
        var statuses: [String: NDKRelayConnectionState] = [:]
        for relay in relays {
            let url = await relay.url
            let state = await relay.connectionState
            statuses[url] = state
        }
        
        self.relayStatuses = statuses
    }
    
    @MainActor
    private func updateRelayConnections() async {
        await nostrManager.updateRelays(relayManager.relays)
        await refreshRelayStatuses()
    }
}

struct RelayRowView: View {
    let url: String
    let status: NDKRelayConnectionState
    let onDelete: () -> Void
    
    var statusColor: Color {
        switch status {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .red
        case .failed:
            return .red
        case .disconnecting:
            return .orange
        @unknown default:
            return .gray
        }
    }
    
    var statusText: String {
        switch status {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return "Disconnected"
        case .failed:
            return "Error"
        case .disconnecting:
            return "Disconnecting..."
        @unknown default:
            return "Unknown"
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(url)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct AddRelayView: View {
    @Binding var relayURL: String
    let onAdd: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var isValidURL = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("wss://relay.example.com", text: $relayURL)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: relayURL) { _, newValue in
                            isValidURL = isValidRelayURL(newValue)
                        }
                } header: {
                    Text("Relay URL")
                } footer: {
                    if !relayURL.isEmpty && !isValidURL {
                        Text("Please enter a valid WebSocket URL (wss://)")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section {
                    Text("Popular Relays")
                        .font(.headline)
                    
                    ForEach(popularRelays, id: \.self) { relay in
                        Button {
                            relayURL = relay
                        } label: {
                            HStack {
                                Text(relay)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.primary)
                                Spacer()
                                if relayURL == relay {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Relay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onAdd()
                    }
                    .disabled(!isValidURL)
                }
            }
        }
    }
    
    private func isValidRelayURL(_ url: String) -> Bool {
        guard !url.isEmpty else { return false }
        guard url.hasPrefix("wss://") || url.hasPrefix("ws://") else { return false }
        guard URL(string: url) != nil else { return false }
        return true
    }
}

private let popularRelays = [
    "wss://relay.damus.io",
    "wss://relay.nostr.band",
    "wss://nos.lol",
    "wss://relay.snort.social",
    "wss://relay.nostr.info",
    "wss://nostr-pub.wellorder.net",
    "wss://relay.current.fyi",
    "wss://relay.nostr.wirednet.jp"
]