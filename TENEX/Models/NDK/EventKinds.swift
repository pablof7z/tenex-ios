import Foundation
import NDKSwift

// TENEX-specific event kinds
struct TENEXEventKind {
    // Chat and Conversations
    static let chat: Kind = 11
    static let threadReply: Kind = 1111
    
    // TENEX Core Events
    static let task: Kind = 1934
    static let project: Kind = 31933
    
    // Agent Events
    static let agentConfig: Kind = 4199
    static let agentLesson: Kind = 4129
    static let agentRequest: Kind = 4133
    static let agentRequestList: Kind = 4134
    
    // MCP Tool Events
    static let mcpTool: Kind = 4200
    
    // Status Events (24xxx series)
    static let projectStatus: Kind = 24010
    static let llmConfigChange: Kind = 24020 // Web client uses 24020
    static let typingIndicator: Kind = 24111
    static let typingIndicatorStop: Kind = 24112
    static let taskAbort: Kind = 24133
    static let projectControl: Kind = 24001 // Ephemeral event for project start/stop requests
    
    // Addressable Events
    static let article: Kind = 30023
    static let template: Kind = 30717
}