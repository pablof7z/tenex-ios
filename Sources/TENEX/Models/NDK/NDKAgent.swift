import Foundation
import NDKSwift
import Observation

@Observable
class NDKAgent: Identifiable {
    let event: NDKEvent
    let id: String
    let pubkey: String
    
    var slug: String
    var name: String
    var title: String
    var description: String?
    var role: String?
    var instructions: String // Markdown content
    var useCriteria: String?
    var version: String?
    var tags: [String] = []
    
    static let kind: Kind = TENEXEventKind.agentConfig
    
    init(event: NDKEvent) {
        self.event = event
        self.id = event.id
        self.pubkey = event.pubkey
        
        // Parse slug from d tag (not used, but keeping for compatibility)
        self.slug = event.id // Use event ID as slug
        
        // Instructions are in the content field (markdown)
        self.instructions = event.content
        
        // Parse metadata from tags
        let parsedTitle = event.tags.first(where: { $0.first == "title" })?.dropFirst().first ?? "Untitled Agent"
        self.title = parsedTitle
        self.name = parsedTitle
        
        self.description = event.tags.first(where: { $0.first == "description" })?.dropFirst().first
        self.role = event.tags.first(where: { $0.first == "role" })?.dropFirst().first
        self.useCriteria = event.tags.first(where: { $0.first == "use-criteria" })?.dropFirst().first
        self.version = event.tags.first(where: { $0.first == "ver" })?.dropFirst().first
        
        // Parse t tags
        self.tags = event.tags
            .filter { $0.first == "t" }
            .compactMap { $0.count > 1 ? String($0[1]) : nil }
    }
    
    // Create mention tag using p tag
    var mentionTag: [String] {
        ["p", id] // Use p tag for mentions
    }
    
    // Update agent from newer event
    func update(from event: NDKEvent) {
        // Update instructions
        if !event.content.isEmpty {
            self.instructions = event.content
        }
        
        // Update title
        if let newTitle = event.tags.first(where: { $0.first == "title" })?.dropFirst().first {
            self.title = newTitle
            self.name = newTitle
        }
        
        // Update other metadata
        if let newDescription = event.tags.first(where: { $0.first == "description" })?.dropFirst().first {
            self.description = newDescription
        }
        if let newRole = event.tags.first(where: { $0.first == "role" })?.dropFirst().first {
            self.role = newRole
        }
        if let newUseCriteria = event.tags.first(where: { $0.first == "use-criteria" })?.dropFirst().first {
            self.useCriteria = newUseCriteria
        }
        if let newVersion = event.tags.first(where: { $0.first == "ver" })?.dropFirst().first {
            self.version = newVersion
        }
        
        // Update tags
        let newTags = event.tags
            .filter { $0.first == "t" }
            .compactMap { $0.count > 1 ? String($0[1]) : nil }
        if !newTags.isEmpty {
            self.tags = newTags
        }
    }
}