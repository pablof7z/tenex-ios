import Foundation
import NDKSwift
import Observation

@Observable
class NDKLesson: Identifiable {
    let event: NDKEvent
    let id: String
    let agentPubkey: String
    let projectId: String
    
    var title: String
    var content: String
    var createdAt: Date
    var tags: [[String]]
    
    static let kind: Kind = TENEXEventKind.agentLesson
    
    init(event: NDKEvent) {
        self.event = event
        self.id = event.id
        self.agentPubkey = event.pubkey
        self.createdAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        self.tags = event.tags
        
        // Extract project ID from a tag
        self.projectId = event.tags.first(where: { $0.first == "a" })?.dropFirst().first ?? ""
        
        // Parse content as JSON if possible
        if let data = event.content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.title = json["title"] as? String ?? "Untitled Lesson"
            self.content = json["content"] as? String ?? event.content
        } else {
            // Fallback to raw content
            self.title = event.tags.first(where: { $0.first == "title" })?.dropFirst().first ?? "Untitled Lesson"
            self.content = event.content
        }
    }
    
    // Helper to get the agent's name if available
    var agentName: String? {
        event.tags.first(where: { $0.first == "agent-name" })?.dropFirst().first
    }
    
    // Helper to get lesson type if available
    var lessonType: String? {
        event.tags.first(where: { $0.first == "lesson-type" })?.dropFirst().first
    }
}