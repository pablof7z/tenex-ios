import Foundation
import NDKSwift
import Observation

// Project Status Event
@Observable
class NDKProjectStatus {
    let event: NDKEvent
    let projectId: String
    let timestamp: Date
    
    var availableAgents: [AgentStatus] = []
    
    static let kind: Kind = TENEXEventKind.projectStatus
    
    struct AgentStatus: Identifiable {
        let id: String
        let slug: String
        let name: String
        let status: String
        let lastSeen: Date?
    }
    
    init(event: NDKEvent) {
        self.event = event
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        
        // Extract project ID from tags
        // The a-tag format can be:
        // ["a", "kind:pubkey:identifier"] or
        // ["a", "kind:pubkey:identifier", "relay-url"]
        if let aTag = event.tags.first(where: { $0.first == "a" }),
           aTag.count >= 2 {
            let fullId = aTag[1]
            // Remove relay URL if present (everything after the second colon after kind)
            let components = fullId.split(separator: ":", maxSplits: 2)
            if components.count >= 3 {
                // Reconstruct without relay: kind:pubkey:identifier
                self.projectId = "\(components[0]):\(components[1]):\(components[2])"
            } else {
                self.projectId = fullId
            }
        } else {
            self.projectId = ""
        }
        
        print("📊 NDKProjectStatus init - Event ID: \(event.id)")
        print("📊 NDKProjectStatus init - Project ID: \(projectId)")
        print("📊 NDKProjectStatus init - Total tags: \(event.tags.count)")
        
        // Debug print all tags
        for (index, tag) in event.tags.enumerated() {
            print("📊 NDKProjectStatus init - Tag[\(index)]: \(tag)")
        }
        
        // Parse available agents from tags
        // Format: ["agent", "<agent-pubkey>", "<agent-slug>"]
        self.availableAgents = event.tags.compactMap { tag in
            guard tag.count >= 3,
                  tag[0] == "agent" else {
                return nil
            }
            
            let pubkey = tag[1]
            let slug = tag[2]
            
            print("📊 NDKProjectStatus init - Found agent: pubkey=\(pubkey), slug=\(slug)")
            
            return AgentStatus(
                id: pubkey,
                slug: slug,
                name: slug, // Using slug as name for now
                status: "available",
                lastSeen: nil
            )
        }
        
        print("📊 NDKProjectStatus init - Total agents found: \(self.availableAgents.count)")
    }
    
    // Update status from newer event
    func update(from event: NDKEvent) {
        // Parse available agents from tags
        // Format: ["agent", "<agent-pubkey>", "<agent-slug>"]
        self.availableAgents = event.tags.compactMap { tag in
            guard tag.count >= 3,
                  tag[0] == "agent" else {
                return nil
            }
            
            let pubkey = tag[1]
            let slug = tag[2]
            
            return AgentStatus(
                id: pubkey,
                slug: slug,
                name: slug, // Using slug as name for now
                status: "available",
                lastSeen: nil
            )
        }
    }
}

// Typing Indicator Event
@Observable
class NDKTypingIndicator {
    let event: NDKEvent
    let conversationId: String
    let projectId: String
    let message: String
    let timestamp: Date
    let phase: String?
    
    static let kind: Kind = TENEXEventKind.typingIndicator
    static let stopKind: Kind = TENEXEventKind.typingIndicatorStop
    
    init(event: NDKEvent) {
        self.event = event
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        
        // Extract conversation ID from e tag
        self.conversationId = event.tags.first(where: { $0.first == "e" })?.dropFirst().first ?? ""
        
        // Extract project ID from a tag
        self.projectId = event.tags.first(where: { $0.first == "a" })?.dropFirst().first ?? ""
        
        // Extract phase from phase tag
        self.phase = event.tags.first(where: { $0.first == "phase" })?.dropFirst().first
        
        // Content contains the typing message
        self.message = event.content
    }
    
    // Check if indicator is still valid (within 60 seconds)
    var isValid: Bool {
        Date().timeIntervalSince(timestamp) < 60
    }
    
    // Create typing indicator builder
    func builder(ndk: NDK) -> NDKEventBuilder {
        return NDKEventBuilder(ndk: ndk)
            .kind(Self.kind)
            .tag(["e", conversationId])
            .tag(["a", projectId])
    }
}

// Task Abort Event - Ephemeral event kind 24133
@Observable
class NDKTaskAbort {
    let event: NDKEvent
    let taskId: String
    let timestamp: Date
    
    static let kind: Kind = TENEXEventKind.taskAbort
    
    init(event: NDKEvent) {
        self.event = event
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        
        // Extract task ID from e tag
        self.taskId = event.tags.first(where: { $0.first == "e" })?.dropFirst().first ?? ""
    }
    
    // Create abort builder
    func builder(ndk: NDK) -> NDKEventBuilder {
        return NDKEventBuilder(ndk: ndk)
            .kind(Self.kind)
            .tag(["e", taskId])
    }
}

// LLM Config Change Event
@Observable
class NDKLLMConfigChange {
    let event: NDKEvent
    let projectId: String
    let timestamp: Date
    
    var model: String?
    var temperature: Double?
    var maxTokens: Int?
    var provider: String?
    
    static let kind: Kind = 24020 // Web client uses 24020
    
    init(event: NDKEvent) {
        self.event = event
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        
        // Extract project ID
        self.projectId = event.tags.first(where: { $0.first == "a" })?.dropFirst().first ?? ""
        
        // Parse config from content (JSON)
        if let contentData = event.content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] {
            self.model = json["model"] as? String
            self.temperature = json["temperature"] as? Double
            self.maxTokens = json["maxTokens"] as? Int
            self.provider = json["provider"] as? String
        }
    }
    
    // Create config builder
    func configBuilder(ndk: NDK) throws -> NDKEventBuilder {
        var config: [String: Any] = [:]
        
        if let model = model {
            config["model"] = model
        }
        if let temperature = temperature {
            config["temperature"] = temperature
        }
        if let maxTokens = maxTokens {
            config["maxTokens"] = maxTokens
        }
        if let provider = provider {
            config["provider"] = provider
        }
        
        let content = try JSONSerialization.data(withJSONObject: config)
        let contentString = String(data: content, encoding: .utf8) ?? "{}"
        
        return NDKEventBuilder(ndk: ndk)
            .content(contentString)
            .kind(Self.kind)
            .tag(["a", projectId])
    }
}