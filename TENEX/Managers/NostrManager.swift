import Foundation
import NDKSwift
import SwiftUI
import Observation

@MainActor
@Observable
class NostrManager: NDKNostrManager {
    // MARK: - TENEX-specific Properties
    
    // Project status tracking
    var projectStatuses: [String: NDKProjectStatus] = [:] // projectId -> status
    var onlineProjects: Set<String> = [] // Set of online project IDs
    private var statusMonitoringTask: Task<Void, Never>?
    private var userProjects: [NDKProject] = []
    
    // MARK: - Configuration Overrides
    
    override var defaultRelays: [String] {
        [
            "wss://relay.primal.net",
            "wss://relay.damus.io",
            "wss://relay.nostr.band",
            "wss://nos.lol",
            "wss://relay.snort.social"
        ]
    }
    
    override var userRelaysKey: String {
        "TENEXUserAddedRelays"
    }
    
    override var clientTagConfig: NDKClientTagConfig? {
        NDKClientTagConfig(
            name: "TENEX",
            autoTag: true
        )
    }
    
    override var sessionConfiguration: NDKSessionConfiguration {
        NDKSessionConfiguration(
            dataRequirements: [.followList],
            preloadStrategy: .progressive
        )
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    deinit {
        Task { @MainActor in
            statusMonitoringTask?.cancel()
        }
    }
    
    // MARK: - Project Status Monitoring
    
    func startStatusMonitoring(for user: NDKUser) async {
        // Cancel existing monitoring
        statusMonitoringTask?.cancel()
        
        statusMonitoringTask = Task {
            // Stream projects as they arrive - never wait!
            for await project in user.streamProjects(maxAge: 300) {
                await MainActor.run {
                    // Update or add project
                    if let index = self.userProjects.firstIndex(where: { $0.addressableId == project.addressableId }) {
                        self.userProjects[index] = project
                    } else {
                        self.userProjects.append(project)
                    }
                }
                
                // Start monitoring status for this specific project immediately
                Task {
                    await monitorProjectStatus(for: project)
                }
            }
        }
    }
    
    private func monitorProjectStatuses() async {
        guard let ndk = ndk else { return }
        
        // Create filters for project status events
        for project in userProjects {
            await monitorProjectStatus(for: project)
        }
    }
    
    private func monitorProjectStatus(for project: NDKProject) async {
        guard let ndk = ndk else { return }
        
        let statusFilter = NDKFilter(
            kinds: [TENEXEventKind.projectStatus],
            tags: ["a": Set([project.addressableId])]
        )
        
        // Stream status events as they arrive
        let dataSource = ndk.observe(
            filter: statusFilter,
            maxAge: 0, // Always get fresh status updates
            cachePolicy: .cacheWithNetwork
        )
        
        // Process events as they stream in
        for await event in dataSource.events {
            let status = NDKProjectStatus(event: event)
            if !status.projectId.isEmpty {
                await MainActor.run {
                    projectStatuses[project.id] = status
                    // For now, consider all projects with status as online
                    onlineProjects.insert(project.id)
                }
            }
        }
    }
    
    func stopStatusMonitoring() {
        statusMonitoringTask?.cancel()
        statusMonitoringTask = nil
    }
    
    // MARK: - Conversation Management
    
    func fetchConversations(for pubkey: String) async throws -> [NDKConversation] {
        guard let ndk = ndk else { throw NDKError.notConfigured("NDK not initialized") }
        
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [TENEXEventKind.chat]
        )
        
        let dataSource = ndk.observe(
            filter: filter,
            maxAge: 600, // Use cache if less than 10 minutes old
            cachePolicy: .cacheWithNetwork
        )
        
        var conversations: [NDKConversation] = []
        
        for await event in dataSource.events {
            let conversation = NDKConversation(event: event)
            if !conversation.projectId.isEmpty {
                conversations.append(conversation)
            }
        }
        
        return conversations
    }
    
    // MARK: - Task Management
    
    func fetchTasks(for projectId: String) async throws -> [NDKTask] {
        guard let ndk = ndk else { throw NDKError.notConfigured("NDK not initialized") }
        
        let filter = NDKFilter(
            kinds: [TENEXEventKind.task],
            tags: ["a": Set([projectId])]
        )
        
        let dataSource = ndk.observe(
            filter: filter,
            maxAge: 300,
            cachePolicy: .cacheWithNetwork
        )
        
        var tasks: [NDKTask] = []
        
        for await event in dataSource.events {
            let task = NDKTask(event: event)
            if !task.projectId.isEmpty {
                tasks.append(task)
            }
        }
        
        return tasks
    }
    
    // MARK: - Agent Management
    
    func getAvailableAgents(for projectId: String) -> [NDKProjectStatus.AgentStatus] {
        if let status = projectStatuses[projectId] {
            return status.availableAgents
        }
        return []
    }
    
    // MARK: - Conversation Creation
    
    func createConversation(
        in project: NDKProject,
        title: String? = nil,
        content: String,
        mentionedAgentPubkeys: [String] = []
    ) async throws -> NDKConversation {
        guard let ndk = ndk, let signer = ndk.signer else {
            throw NDKError.notConfigured("NDK not initialized or no signer available")
        }
        
        var builder = NDKEventBuilder(ndk: ndk)
            .content(content)
            .kind(TENEXEventKind.chat)
            .tag(["a", project.addressableId])
        
        if let title = title {
            builder = builder.tag(["title", title])
        }
        
        for agentPubkey in mentionedAgentPubkeys {
            builder = builder.tag(["p", agentPubkey])
        }
        
        let event = try await builder.build(signer: signer)
        let publishedRelays = try await ndk.publish(event)
        
        print("Created conversation on \(publishedRelays.count) relays")
        
        return NDKConversation(event: event)
    }
}

