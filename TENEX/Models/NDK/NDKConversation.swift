import Foundation
import NDKSwift
import Observation

@Observable
class NDKConversation: Identifiable {
    let event: NDKEvent
    let id: String
    let projectId: String
    
    var title: String
    var content: String
    var createdAt: Date
    var author: String
    var lastReply: NDKEvent?
    var replyCount: Int = 0
    var mentionedAgents: [String] = [] // agent pubkeys
    var phase: String? // Current phase from status updates
    
    static let kind: Kind = TENEXEventKind.chat
    
    init(event: NDKEvent) {
        self.event = event
        self.id = event.id
        self.author = event.pubkey
        self.content = event.content
        self.createdAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        
        // Extract project ID from a tag first
        self.projectId = event.tags.first(where: { $0.first == "a" })?.dropFirst().first ?? ""
        
        // Extract title from tags or content
        if let titleTag = event.tags.first(where: { $0.first == "title" }) {
            self.title = titleTag.dropFirst().first ?? "Untitled"
        } else {
            // Use first line of content as title
            self.title = event.content.components(separatedBy: .newlines).first ?? "Untitled"
        }
        
        // Extract mentioned agents from p tags
        self.mentionedAgents = event.tags
            .filter { $0.first == "p" }
            .compactMap { $0.count > 1 ? String($0[1]) : nil }
    }
    
    // Extract replies count from thread metadata
    func updateFromThreadMetadata(_ event: NDKEvent) {
        if let replyCountStr = event.tags.first(where: { $0.first == "reply-count" })?.dropFirst().first,
           let count = Int(replyCountStr) {
            self.replyCount = count
        }
        
        // Update last reply timestamp if available
        if let lastReplyStr = event.tags.first(where: { $0.first == "last-reply" })?.dropFirst().first,
           let _ = Int(lastReplyStr) {
            // We'd need to fetch the actual event, but at least we have the timestamp
        }
    }
    
    // Create a reply builder for this conversation
    func replyBuilder(ndk: NDK) -> NDKEventBuilder {
        return NDKEventBuilder.reply(to: event, ndk: ndk)
            .kind(TENEXEventKind.threadReply)
            .tag(["a", projectId])
    }
}