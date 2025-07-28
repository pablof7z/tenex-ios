import Foundation
import SwiftUI

// Default relays
let DEFAULT_RELAYS = [
    "wss://relay.primal.net",
    "wss://relay.damus.io",
    "wss://relay.nostr.band",
    "wss://nos.lol",
    "wss://relay.snort.social"
]

// UserDefaults key for relay storage
let RELAY_STORAGE_KEY = "com.tenex.relays"

class RelayManager: ObservableObject {
    static let shared = RelayManager()
    
    @Published var relays: [String] = []
    
    private init() {
        loadRelays()
    }
    
    func loadRelays() {
        if let savedRelays = UserDefaults.standard.array(forKey: RELAY_STORAGE_KEY) as? [String], !savedRelays.isEmpty {
            relays = savedRelays
        } else {
            relays = DEFAULT_RELAYS
            saveRelays()
        }
    }
    
    func saveRelays() {
        UserDefaults.standard.set(relays, forKey: RELAY_STORAGE_KEY)
    }
    
    func addRelay(_ url: String) {
        guard !url.isEmpty && !relays.contains(url) else { return }
        relays.append(url)
        saveRelays()
    }
    
    func removeRelay(_ url: String) {
        relays.removeAll { $0 == url }
        saveRelays()
    }
    
    func resetToDefaults() {
        relays = DEFAULT_RELAYS
        saveRelays()
    }
}