import Foundation
import NDKSwift
import SwiftUI
import Observation

@MainActor
@Observable
class NostrManager {
    var ndk: NDK
    var isConnected = false
    var cache: NDKSQLiteCache?
    var sessionState: NDKAuthManager.SessionState = .noSession
    
    // Project status tracking
    var projectStatuses: [String: NDKProjectStatus] = [:] // projectId -> status
    var onlineProjects: Set<String> = [] // Set of online project IDs
    private var statusMonitoringTask: Task<Void, Never>?
    private var userProjects: [NDKProject] = []
    
    private let ndkAuthManager = NDKAuthManager.shared
    private var authStateObservation: Task<Void, Never>?
    
    init() {
        // Initialize NDK with persisted relays
        let relayUrls = RelayManager.shared.relays
        self.ndk = NDK(relayUrls: relayUrls)
        setupNDK()
    }
    
    private func setupNDK() {
        Task {
            do {
                let cache = try await NDKSQLiteCache()
                self.cache = cache
                
                // Create new NDK with cache and persisted relays
                let relayUrls = RelayManager.shared.relays
                ndk = NDK(relayUrls: relayUrls, cache: cache)
                
                await ndk.connect()
                isConnected = true
                
                ndkAuthManager.setNDK(ndk)
                print("NDK initialized with SQLite cache")
            } catch {
                print("Failed to initialize SQLite cache: \(error). Using NDK without cache.")
                
                // Connect without cache
                await ndk.connect()
                isConnected = true
                ndkAuthManager.setNDK(ndk)
            }
            
            // Observe session state changes
            _ = withObservationTracking {
                ndkAuthManager.sessionState
            } onChange: { [weak self] in
                Task { @MainActor in
                    await self?.handleAuthStateChange()
                }
            }
            
            // Handle initial state
            await handleAuthStateChange()
        }
    }
    
    private func handleAuthStateChange() async {
        sessionState = ndkAuthManager.sessionState
        
        switch ndkAuthManager.sessionState {
        case .active:
            // If authenticated, ensure signer is set on NDK
            if let activeSigner = ndkAuthManager.activeSigner {
                ndk.signer = activeSigner
                print("Setting active signer on NDK")
                
                // Start session if not already started
                if ndk.sessionData == nil {
                    do {
                        _ = try await ndk.startSession(
                            signer: activeSigner,
                            config: NDKSessionConfiguration(
                                dataRequirements: [.followList],
                                preloadStrategy: .progressive
                            )
                        )
                        print("Session data loaded successfully")
                    } catch {
                        print("Failed to start session: \(error)")
                    }
                }
                
                // Log session status
                if ndkAuthManager.activeSession != nil {
                    print("Session is ready with user: \(currentUser?.pubkey ?? "nil")")
                }
            }
            
        case .noSession:
            // Clear signer if no session
            ndk.signer = nil
            
        default:
            break
        }
    }
    
    // Get auth manager for use in UI
    var authManager: NDKAuthManager {
        return ndkAuthManager
    }
    
    // Check if user is authenticated
    var isAuthenticated: Bool {
        ndkAuthManager.hasActiveSession && ndk.signer != nil
    }
    
    // Get current user from active session
    var currentUser: NDKUser? {
        guard let session = ndkAuthManager.activeSession else { 
            print("NostrManager.currentUser: No active session found")
            return nil 
        }
        let user = NDKUser(pubkey: session.pubkey)
        print("NostrManager.currentUser: Returning user with session pubkey \(session.pubkey)")
        return user
    }
    
    func logout() {
        // Clear cache data
        Task {
            if let cache = cache {
                try? await cache.clear()
                print("Cleared all cached data")
            }
            
            // Delete all sessions from keychain
            for session in ndkAuthManager.availableSessions {
                try? await ndkAuthManager.removeSession(session)
                print("Deleted session for pubkey: \(session.pubkey)")
            }
        }
        
        // Let NDKAuthManager handle session logout
        ndkAuthManager.logout()
    }
    
    // MARK: - Event Publishing
    
    func createConversation(
        in project: NDKProject,
        title: String? = nil,
        content: String,
        mentionedAgentPubkeys: [String] = []
    ) async throws -> NDKConversation {
        var builder = NDKEventBuilder(ndk: ndk)
            .content(content)
            .kind(NDKConversation.kind)
            .tag(["a", project.addressableId])
        
        if let title = title {
            builder = builder.tag(["title", title])
        }
        
        // Add agent mentions using p tags
        for agentPubkey in mentionedAgentPubkeys {
            builder = builder.tag(["p", agentPubkey])
        }
        
        let event = try await builder.build()
        
        // Publish with optimistic updates
        _ = try await ndk.publish(event)
        
        // Return conversation (will be immediately available through optimistic publishing)
        return NDKConversation(event: event)
    }
    
    func replyToConversation(
        _ conversation: NDKConversation,
        content: String,
        mentionedAgentPubkeys: [String] = [],
        lastVisibleMessage: NDKEvent? = nil
    ) async throws -> NDKEvent {
        // Use NDKSwift's NIP-22 support for thread replies
        var builder = NDKEventBuilder.reply(to: conversation.event, ndk: ndk)
            .content(content)
            .tag(["a", conversation.projectId])  // Add project reference
        
        // Add p-tags based on mentions or last visible message
        if !mentionedAgentPubkeys.isEmpty {
            // Add explicitly mentioned agents
            for agentPubkey in mentionedAgentPubkeys {
                builder = builder.tag(["p", agentPubkey])
            }
        } else if let lastMessage = lastVisibleMessage,
                  lastMessage.pubkey != currentUser?.pubkey {
            // P-tag the last visible message if it's not from current user
            builder = builder.tag(["p", lastMessage.pubkey])
        }

        let event = try await builder.build()
        
        // Sign and publish
        _ = try await ndk.publish(event)
        
        return event
    }
    
    func requestProjectStart(project: NDKProject) async {
        // Create ephemeral event to request project start
        let builder = NDKEventBuilder(ndk: ndk)
            .kind(TENEXEventKind.projectStatus)
            .content("")
            .tag(["a", project.addressableId])
            .tag(["request", "start"])
        
        do {
            // Build and publish the ephemeral event
            let event = try await builder.build()
            _ = try await ndk.publish(event)
            print("Sent project start request for \(project.addressableId)")
        } catch {
            print("Failed to send project start request: \(error)")
        }
    }
    
    // MARK: - Project Status Monitoring
    
    func startProjectStatusMonitoring(for projects: [NDKProject]) {
        print("🚀 NostrManager: startProjectStatusMonitoring called with \(projects.count) projects")
        for project in projects {
            print("🚀 NostrManager: Project: \(project.name) - \(project.addressableId)")
        }
        
        // Update user projects
        userProjects = projects
        
        // Cancel existing monitoring if any
        statusMonitoringTask?.cancel()
        
        // Start new monitoring task
        statusMonitoringTask = Task {
            await monitorProjectStatuses()
        }
    }
    
    func stopProjectStatusMonitoring() {
        statusMonitoringTask?.cancel()
        statusMonitoringTask = nil
        projectStatuses.removeAll()
        onlineProjects.removeAll()
    }
    
    private func monitorProjectStatuses() async {
        // Create filter for all project status events
        let projectIds = Set(userProjects.map { $0.addressableId })
        print("🔍 NostrManager: Starting monitoring for projects: \(projectIds)")
        print("🔍 NostrManager: NDKProjectStatus.kind = \(NDKProjectStatus.kind) (should be 24010)")
        
        let statusFilter = NDKFilter(
            kinds: [NDKProjectStatus.kind],
            tags: ["a": projectIds]
        )
        
        print("🔍 NostrManager: Created filter with kind \(NDKProjectStatus.kind) for \(projectIds.count) projects")
        print("🔍 NostrManager: Filter tags - a: \(Array(projectIds))")
        print("🔍 NostrManager: Filter details:")
        print("🔍 NostrManager:   - kinds: \(statusFilter.kinds)")
        print("🔍 NostrManager:   - tags: \(statusFilter.tags)")
        
        // Also verify what we're actually filtering for
        for projectId in projectIds {
            print("🔍 NostrManager: Monitoring for project ID: '\(projectId)'")
        }
        
        let statusSource = ndk.observe(
            filter: statusFilter,
            maxAge: 0, // Real-time
            cachePolicy: .networkOnly
        )
        
        print("🔍 NostrManager: Started observing project status events")
        
        // Track EOSE from relays
        var receivedEOSE = Set<String>()
        var hasStartedStatusSubscription = false
        
        // Monitor relay updates to wait for EOSE
        Task {
            print("🔍 NostrManager: Monitoring relay updates for EOSE...")
            for await update in statusSource.relayUpdates {
                switch update {
                case .eose(let relay):
                    receivedEOSE.insert(relay)
                    print("📥 NostrManager: Received EOSE from relay: \(relay)")
                    print("📥 NostrManager: Total EOSE received: \(receivedEOSE.count)")
                    
                    // Start status subscription after first EOSE
                    if !hasStartedStatusSubscription && !receivedEOSE.isEmpty {
                        hasStartedStatusSubscription = true
                        print("✅ NostrManager: First EOSE received, starting 24010 status subscription")
                    }
                    
                case .event(let event, let relay):
                    print("📥 NostrManager: Received event \(event.id) \(event.kind) in task from relay: \(relay)")
                    
                case .closed(let relay):
                    print("❌ NostrManager: Subscription closed on relay: \(relay)")
                }
            }
        }
        
        print("🔍 NostrManager: Starting event observation loop...")
        
        for await event in statusSource.events {
            // Only process status events after we've received at least one EOSE
            guard hasStartedStatusSubscription else {
                print("⏳ NostrManager: Waiting for EOSE before processing status event: \(event.id)")
                continue
            }
            print("📥 NostrManager: Received event with ID: \(event.id)")
            print("📥 NostrManager: Event kind: \(event.kind) (expected: \(NDKProjectStatus.kind))")
            print("📥 NostrManager: Event pubkey: \(event.pubkey)")
            print("📥 NostrManager: Event tags: \(event.tags)")
            print("📥 NostrManager: Event content: \(event.content)")
            
            // Verify this is a project status event
            guard event.kind == NDKProjectStatus.kind else {
                print("⚠️ NostrManager: Received unexpected event kind: \(event.kind), expected: \(NDKProjectStatus.kind)")
                continue
            }
            
            let status = NDKProjectStatus(event: event)
            
            print("📥 NostrManager: Parsed status - projectId: \(status.projectId)")
            print("📥 NostrManager: Available agents: \(status.availableAgents.count)")
            for agent in status.availableAgents {
                print("📥 NostrManager:   - Agent: \(agent.slug) (pubkey: \(agent.id))")
            }
            
            // Check if this project ID matches any of our monitored projects
            let matchingProject = userProjects.first { project in
                let matches = project.addressableId == status.projectId
                print("📥 NostrManager: Comparing '\(project.addressableId)' with '\(status.projectId)': \(matches)")
                return matches
            }
            
            if matchingProject != nil {
                print("✅ NostrManager: Found matching project for status update")
                
                // Update project status
                projectStatuses[status.projectId] = status
                print("✅ NostrManager: Updated projectStatuses - now have \(projectStatuses.count) statuses")
                
                // Update online status (considered online if status is less than 90 seconds old)
                if status.timestamp.timeIntervalSinceNow > -90 {
                    onlineProjects.insert(status.projectId)
                    print("✅ NostrManager: Project \(status.projectId) is ONLINE")
                } else {
                    onlineProjects.remove(status.projectId)
                    print("⚠️ NostrManager: Project \(status.projectId) is OFFLINE (age: \(-status.timestamp.timeIntervalSinceNow)s)")
                }
                
                // Request project start if offline
                if !onlineProjects.contains(status.projectId) {
                    print("🔄 NostrManager: Requesting start for offline project \(status.projectId)")
                    await requestProjectStart(project: matchingProject!)
                }
            } else {
                print("⚠️ NostrManager: No matching project found for status projectId: \(status.projectId)")
                print("⚠️ NostrManager: Monitored project IDs: \(userProjects.map { $0.addressableId })")
            }
        }
        
        print("🔍 NostrManager: Event observation loop ended")
    }
    
    // Get available agents for a project
    func getAvailableAgents(for projectId: String) -> [NDKProjectStatus.AgentStatus] {
        print("🔍 NostrManager: Getting agents for project \(projectId)")
        guard let status = projectStatuses[projectId] else { 
            print("🔍 NostrManager: No status found for project \(projectId)")
            print("🔍 NostrManager: Current statuses: \(projectStatuses.keys)")
            return [] 
        }
        print("🔍 NostrManager: Returning \(status.availableAgents.count) agents")
        return status.availableAgents
    }
    
    // Check if project is online
    func isProjectOnline(_ projectId: String) -> Bool {
        return onlineProjects.contains(projectId)
    }
    
    // MARK: - Relay Management
    
    func updateRelays(_ relayUrls: [String]) async {
        // Disconnect from current relays
        await ndk.disconnect()
        
        // Create new NDK instance with updated relays
        if let cache = cache {
            ndk = NDK(relayUrls: relayUrls, cache: cache)
        } else {
            ndk = NDK(relayUrls: relayUrls)
        }
        
        // Set signer if authenticated
        if let activeSigner = ndkAuthManager.activeSigner {
            ndk.signer = activeSigner
        }
        
        // Reconnect
        await ndk.connect()
        isConnected = true
        
        // Update auth manager's NDK reference
        ndkAuthManager.setNDK(ndk)
        
        // Restart session if authenticated
        if isAuthenticated, let activeSigner = ndkAuthManager.activeSigner {
            do {
                _ = try await ndk.startSession(
                    signer: activeSigner,
                    config: NDKSessionConfiguration(
                        dataRequirements: [.followList],
                        preloadStrategy: .progressive
                    )
                )
                print("Session restarted with new relays")
            } catch {
                print("Failed to restart session: \(error)")
            }
        }
        
        // Restart project monitoring if active
        if !userProjects.isEmpty {
            startProjectStatusMonitoring(for: userProjects)
        }
    }
}