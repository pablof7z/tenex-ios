import Foundation
import NDKSwift
import Observation

@Observable
class NDKTask: ObservableObject, Identifiable {
    let event: NDKEvent
    let id: String
    let pubkey: String
    
    var title: String
    var content: String
    var projectId: String
    var status: String?
    var assignees: [String] = [] // pubkeys of assigned agents
    var branch: String?
    var conversationId: String?
    
    static let kind: Kind = TENEXEventKind.task
    
    init(event: NDKEvent) {
        self.event = event
        self.id = event.id
        self.pubkey = event.pubkey
        
        // Content is the task description
        self.content = event.content
        
        // Parse title from tags
        self.title = event.tags.first(where: { $0.first == "title" })?.dropFirst().first ?? "Untitled Task"
        
        // Parse project reference
        self.projectId = event.tags.first(where: { $0.first == "a" })?.dropFirst().first ?? ""
        
        // Parse status
        self.status = event.tags.first(where: { $0.first == "status" })?.dropFirst().first
        
        // Parse assignees (p tags)
        self.assignees = event.tags
            .filter { $0.first == "p" }
            .compactMap { $0.count > 1 ? String($0[1]) : nil }
        
        // Parse branch
        self.branch = event.tags.first(where: { $0.first == "branch" })?.dropFirst().first
        
        // Parse conversation reference
        self.conversationId = event.tags.first(where: { $0.first == "e" })?.dropFirst().first
    }
    
    // Update task from newer event
    func update(from event: NDKEvent) {
        // Update content
        if !event.content.isEmpty {
            self.content = event.content
        }
        
        // Update title
        if let newTitle = event.tags.first(where: { $0.first == "title" })?.dropFirst().first {
            self.title = newTitle
        }
        
        // Update status
        if let newStatus = event.tags.first(where: { $0.first == "status" })?.dropFirst().first {
            self.status = newStatus
        }
        
        // Update assignees
        let newAssignees = event.tags
            .filter { $0.first == "p" }
            .compactMap { $0.count > 1 ? String($0[1]) : nil }
        if !newAssignees.isEmpty {
            self.assignees = newAssignees
        }
        
        // Update branch
        if let newBranch = event.tags.first(where: { $0.first == "branch" })?.dropFirst().first {
            self.branch = newBranch
        }
    }
    
    // Check if task is assigned to a specific agent
    func isAssignedTo(pubkey: String) -> Bool {
        assignees.contains(pubkey)
    }
    
    // Create a reply builder for this task
    // Note: We'll need to manually handle p-tags after building the event
    func replyBuilder(ndk: NDK) -> NDKEventBuilder {
        return NDKEventBuilder.reply(to: event, ndk: ndk)
            .kind(EventKind.genericReply)
    }
}