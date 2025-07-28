import Foundation
import NDKSwift
import Observation

@Observable
class NDKProject: Identifiable {
    let event: NDKEvent
    let id: String
    let pubkey: String
    let identifier: String
    
    var name: String
    var title: String
    var description: String?
    var repo: String?
    var agentIds: [String] = []
    var mcpIds: [String] = []
    
    static let kind: Kind = TENEXEventKind.project
    
    init(event: NDKEvent) {
        self.event = event
        self.id = event.id
        self.pubkey = event.pubkey
        
        // Parse identifier from d tag
        self.identifier = event.tags.first(where: { $0.first == "d" })?.dropFirst().first ?? ""
        
        // Parse title from tags
        let parsedTitle = event.tags.first(where: { $0.first == "title" })?.dropFirst().first ?? identifier
        self.title = parsedTitle
        self.name = parsedTitle
        
        // Content is the description
        self.description = event.content.isEmpty ? nil : event.content
        
        // Parse repo
        self.repo = event.tags.first(where: { $0.first == "repo" })?.dropFirst().first
        
        // Parse agent IDs
        self.agentIds = event.tags
            .filter { $0.first == "agent" }
            .compactMap { $0.count > 1 ? String($0[1]) : nil }
        
        // Parse MCP IDs
        self.mcpIds = event.tags
            .filter { $0.first == "mcp" }
            .compactMap { $0.count > 1 ? String($0[1]) : nil }
    }
    
    // Create addressable reference
    var addressableId: String {
        "\(Self.kind):\(pubkey):\(identifier)"
    }
    
    // Update project from newer event
    func update(from event: NDKEvent) {
        // Update title
        if let newTitle = event.tags.first(where: { $0.first == "title" })?.dropFirst().first {
            self.title = newTitle
            self.name = newTitle
        }
        
        // Update description
        if !event.content.isEmpty {
            self.description = event.content
        }
        
        // Update repo
        if let newRepo = event.tags.first(where: { $0.first == "repo" })?.dropFirst().first {
            self.repo = newRepo
        }
        
        // Update agent IDs
        let newAgentIds = event.tags
            .filter { $0.first == "agent" }
            .compactMap { $0.count > 1 ? String($0[1]) : nil }
        if !newAgentIds.isEmpty {
            self.agentIds = newAgentIds
        }
        
        // Update MCP IDs
        let newMcpIds = event.tags
            .filter { $0.first == "mcp" }
            .compactMap { $0.count > 1 ? String($0[1]) : nil }
        if !newMcpIds.isEmpty {
            self.mcpIds = newMcpIds
        }
    }
}