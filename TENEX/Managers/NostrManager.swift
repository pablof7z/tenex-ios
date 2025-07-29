import Foundation
import NDKSwift
import SwiftUI
import Observation

@MainActor
@Observable
class NostrManager {
    
    // MARK: - TENEX-specific Properties
    
    // Project status tracking
    var projectStatuses: [String: NDKProjectStatus] = [:] // projectId -> status
    var onlineProjects: Set<String> = [] // Set of online project IDs
    private var statusMonitoringTask: Task<Void, Never>?
    private var userProjects: [NDKProject] = []
    
    // LLM config tracking
    var projectLLMConfigs: [String: NDKLLMConfigChange] = [:] // projectId -> latest LLM config
    
    // Conversation tracking
    var projectConversations: [String: [NDKConversation]] = [:] // projectId -> conversations
    
    // Auth manager
    private(set) var authManager: NDKAuthManager?
    
    // Current user
    var currentUser: NDKUser? {
        guard let pubkey = authManager?.activeSession?.pubkey else { return nil }
        return NDKUser(pubkey: pubkey)
    }
    
    // Current user's pubkey (synchronous access)
    var currentUserPubkey: String?
    
    // Authentication status
    var hasActiveUser: Bool {
        isAuthenticated
    }
    
    // MARK: - Core Properties
    
    private(set) var isConnected = false
    private(set) var isInitialized = false
    private var _ndk: NDK?
    
    var ndk: NDK {
        guard let ndk = _ndk else {
            fatalError("NDK accessed before initialization. Check isInitialized before accessing ndk.")
        }
        return ndk
    }
    
    var cache: NDKSQLiteCache?
    var zapManager: NDKZapManager?
    
    // MARK: - Configuration
    
    var defaultRelays: [String] {
        [
            "wss://relay.primal.net"
        ]
    }
    
    var clientTagConfig: NDKClientTagConfig? {
        NDKClientTagConfig(
            name: "TENEX",
            autoTag: true
        )
    }
    
    var appRelaysKey: String {
        "TENEXAddedRelays"
    }
    
    var sessionConfiguration: NDKSessionConfiguration {
        NDKSessionConfiguration(
            dataRequirements: [.followList, .muteList],
            preloadStrategy: .progressive
        )
    }
    
    // MARK: - Computed Properties
    
    var isAuthenticated: Bool {
        authManager?.isAuthenticated ?? false
    }
    
    // MARK: - Initialization
    
    init() {
        Task {
            await setupNDK()
        }
    }
    
    func cleanup() {
        statusMonitoringTask?.cancel()
    }
    
    // MARK: - Cache Management
    
    func clearCache() async throws {
        guard let cache = cache else {
            throw NDKError.notConfigured("No cache available")
        }
        try await cache.clear()
    }
    
    // MARK: - Setup
    
    func setupNDK() async {
        NDKLogger.configure(
            logLevel: .debug,
            enabledCategories: [
                .general,
                .subscription,
                .cache
            ],
            logNetworkTraffic: true
        )
        
        // Initialize SQLite cache for better performance and offline access
        do {
            cache = try await NDKSQLiteCache()
            let allRelays = getAllRelays()
            _ndk = NDK(relayUrls: allRelays, cache: cache)
            NDKLogger.log(.info, category: .general, "NDK initialized with SQLite cache and \(allRelays.count) relays: \(allRelays) (outbox disabled)")
        } catch {
            NDKLogger.log(.error, category: .general, "Failed to initialize SQLite cache: \(error). Continuing without cache.")
            let allRelays = getAllRelays()
            _ndk = NDK(relayUrls: allRelays)
            NDKLogger.log(.info, category: .general, "NDK initialized without cache and \(allRelays.count) relays: \(allRelays) (outbox disabled)")
        }

        // Configure client tags if provided
        if let config = clientTagConfig {
            ndk.clientTagConfig = config
            NDKLogger.log(.info, category: .general, "[NostrManager] Configured NIP-89 client tags")
        }
        
        // Initialize zap manager
        zapManager = NDKZapManager(ndk: ndk)
        NDKLogger.log(.info, category: .general, "[NostrManager] Zap manager initialized")
        
        // Initialize auth manager to restore sessions
        NDKLogger.log(.info, category: .general, "[NostrManager] Initializing auth manager for session restoration")
        authManager = NDKAuthManager(ndk: ndk)
        await authManager?.initialize()
        
        Task {
            await connectToRelays()
        }
        
        // Mark as initialized
        isInitialized = true
        NDKLogger.log(.info, category: .general, "[NostrManager] Initialization complete")
    }
    
    func connectToRelays() async {
        NDKLogger.log(.info, category: .general, "[NostrManager] Connecting to relays...")
        await ndk.connect()
        isConnected = true
        NDKLogger.log(.info, category: .general, "[NostrManager] Connected to relays")
    }
    
    func getAllRelays() -> [String] {
        let appRelays = UserDefaults.standard.stringArray(forKey: appRelaysKey) ?? []
        return Array(Set(defaultRelays + appRelays))
    }
    
    var appAddedRelays: [String] {
        UserDefaults.standard.stringArray(forKey: appRelaysKey) ?? []
    }
    
    func addAppRelay(_ relayURL: String) async {
        var appRelays = appAddedRelays
        if !appRelays.contains(relayURL) && !defaultRelays.contains(relayURL) {
            appRelays.append(relayURL)
            UserDefaults.standard.set(appRelays, forKey: appRelaysKey)
            
            // Add to NDK and connect
            let relay = await ndk.addRelayAndConnect(relayURL)
            if relay != nil {
                NDKLogger.log(.info, category: .general, "Added and connected to relay: \(relayURL)")
            }
        }
    }
    
    func removeAppRelay(_ relayURL: String) async {
        var appRelays = appAddedRelays
        appRelays.removeAll { $0 == relayURL }
        UserDefaults.standard.set(appRelays, forKey: appRelaysKey)
        
        // Don't remove if it's a default relay
        if !defaultRelays.contains(relayURL) {
            await ndk.removeRelay(relayURL)
            NDKLogger.log(.info, category: .general, "Removed relay: \(relayURL)")
        }
    }
    
    // MARK: - User Data Management
    
    func initializeUserData(for pubkey: String) async {
        // Initialize user-specific data
        
        currentUserPubkey = pubkey
        
        // Start monitoring for this user
        let user = NDKUser(pubkey: pubkey)
        await startStatusMonitoring(for: user)
    }
    
    // MARK: - Project Status Monitoring
    
    func startStatusMonitoring(for user: NDKUser) async {
        // Cancel existing monitoring
        statusMonitoringTask?.cancel()
        
        // Start monitoring LLM configs
        Task {
            await monitorLLMConfigs()
        }
        
        statusMonitoringTask = Task {
            // Stream projects for this user
            let projectFilter = NDKFilter(
                authors: [user.pubkey],
                kinds: [TENEXEventKind.project]
            )
            
            let projectSource = ndk.observe(
                filter: projectFilter,
                maxAge: 0,
                cachePolicy: .cacheWithNetwork
            )
            
            for await event in projectSource.events {
                let project = NDKProject(event: event)
                
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
        
        // Create filters for project status events
        for project in userProjects {
            await monitorProjectStatus(for: project)
        }
    }
    
    private func monitorProjectStatus(for project: NDKProject) async {
        
        let statusFilter = NDKFilter(
            kinds: [TENEXEventKind.projectStatus],
            tags: ["a": Set([project.addressableId])]
        )
        
        // Stream status events as they arrive
        let dataSource = ndk.observe(
            filter: statusFilter,
            cachePolicy: .networkOnly
        )
        
        // Process events as they stream in
        for await event in dataSource.events {
            print("📡 monitorProjectStatus - Received status event for project: \(project.id)")
            print("📡 monitorProjectStatus - Event ID: \(event.id)")
            print("📡 monitorProjectStatus - Event content: \(event.content)")
            
            let status = NDKProjectStatus(event: event)
            print("📡 monitorProjectStatus - Parsed status projectId: \(status.projectId)")
            print("📡 monitorProjectStatus - Parsed agents count: \(status.availableAgents.count)")
            
            if !status.projectId.isEmpty {
                await MainActor.run {
                    print("📡 monitorProjectStatus - Storing status for project.addressableId: \(project.addressableId)")
                    projectStatuses[project.addressableId] = status
                    // For now, consider all projects with status as online
                    onlineProjects.insert(project.addressableId)
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
        print("🔍 getAvailableAgents - Looking for project: \(projectId)")
        print("🔍 getAvailableAgents - Current projectStatuses keys: \(projectStatuses.keys)")
        
        if let status = projectStatuses[projectId] {
            print("🔍 getAvailableAgents - Found status for project")
            print("🔍 getAvailableAgents - Available agents count: \(status.availableAgents.count)")
            for agent in status.availableAgents {
                print("🔍 getAvailableAgents - Agent: id=\(agent.id), slug=\(agent.slug), name=\(agent.name)")
            }
            return status.availableAgents
        } else {
            print("🔍 getAvailableAgents - No status found for project: \(projectId)")
        }
        return []
    }
    
    // MARK: - State Access Helpers
    
    /// Get all tracked projects
    var projects: [NDKProject] {
        userProjects
    }
    
    /// Check if a project is online
    func isProjectOnline(_ projectId: String) -> Bool {
        onlineProjects.contains(projectId)
    }
    
    /// Get the full status for a project
    func getProjectStatus(for projectAddressableId: String) -> NDKProjectStatus? {
        projectStatuses[projectAddressableId]
    }
    
    /// Get project by ID
    func getProject(by projectId: String) -> NDKProject? {
        userProjects.first { $0.id == projectId }
    }
    
    /// Get project by addressable ID
    func getProject(byAddressableId addressableId: String) -> NDKProject? {
        userProjects.first { $0.addressableId == addressableId }
    }
    
    /// Get LLM config for a project
    func getLLMConfig(for projectId: String) -> NDKLLMConfigChange? {
        projectLLMConfigs[projectId]
    }
    
    /// Get conversations for a project
    func getConversations(for projectId: String) -> [NDKConversation] {
        projectConversations[projectId] ?? []
    }
    
    // MARK: - Project Control
    
    func requestProjectStart(project: NDKProject) async {
        guard let signer = ndk.signer else { return }
        
        do {
            // Create ephemeral project start request event
            let event = try await NDKEventBuilder(ndk: ndk)
                .content("start")
                .kind(TENEXEventKind.projectControl)
                .tag(["a", project.addressableId])
                .tag(["action", "start"])
                .build(signer: signer)
            
            // Publish as ephemeral event
            let publishedRelays = try await ndk.publish(event)
            print("🚀 Sent project start request to \(publishedRelays.count) relays")
        } catch {
            print("❌ Failed to send project start request: \(error)")
        }
    }
    
    // MARK: - LLM Config Monitoring
    
    func monitorLLMConfigs() async {
        
        // Monitor LLM config changes for all projects
        let configFilter = NDKFilter(
            kinds: [TENEXEventKind.llmConfigChange]
        )
        
        let dataSource = ndk.observe(
            filter: configFilter,
            maxAge: 0, // Always get fresh config updates
            cachePolicy: .cacheWithNetwork
        )
        
        for await event in dataSource.events {
            let config = NDKLLMConfigChange(event: event)
            if !config.projectId.isEmpty {
                await MainActor.run {
                    projectLLMConfigs[config.projectId] = config
                }
            }
        }
    }
    
    // MARK: - Conversation Creation
    
    func createConversation(
        in project: NDKProject,
        title: String? = nil,
        content: String,
        mentionedAgentPubkeys: [String] = []
    ) async throws -> NDKConversation {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer available")
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
    
    // MARK: - Conversation Reply
    
    func replyToConversation(
        _ conversation: NDKConversation,
        content: String,
        mentionedAgentPubkeys: [String] = [],
        lastVisibleMessage: NDKEvent? = nil
    ) async throws -> NDKEvent {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer available")
        }
        
        var builder = NDKEventBuilder(ndk: ndk)
            .content(content)
            .kind(TENEXEventKind.threadReply)
            .tag(["e", conversation.id, "", "root"])
            .tag(["a", conversation.projectId])
        
        // Add reply tag to the last visible message if provided
        if let lastMessage = lastVisibleMessage {
            builder = builder.tag(["e", lastMessage.id, "", "reply"])
        }
        
        // Add pubkey mentions
        for agentPubkey in mentionedAgentPubkeys {
            builder = builder.tag(["p", agentPubkey])
        }
        
        let event = try await builder.build(signer: signer)
        let publishedRelays = try await ndk.publish(event)
        
        print("Created reply on \(publishedRelays.count) relays")
        
        return event
    }
    
    // MARK: - User Management
    
    @MainActor
    private func updateCurrentUserPubkey() {
        if let user = currentUser {
            currentUserPubkey = user.pubkey
        } else {
            currentUserPubkey = nil
        }
    }
    
    // MARK: - Authentication
    
    func login(with privateKey: String) async throws {
        guard isInitialized else {
            throw NDKError.notConfigured("NDK not initialized")
        }
        
        // Create signer
        let signer: NDKPrivateKeySigner
        if privateKey.hasPrefix("nsec1") {
            signer = try NDKPrivateKeySigner(nsec: privateKey)
        } else {
            signer = try NDKPrivateKeySigner(privateKey: privateKey)
        }
        
        // Add session using auth manager
        guard let authManager = authManager else {
            throw NDKError.notConfigured("Auth manager not initialized")
        }
        _ = try await authManager.addSession(signer)
        
        // Get the pubkey from the active session
        if let pubkey = authManager.activePubkey {
            await initializeUserData(for: pubkey)
        }
    }
    
    func logout() {
        guard isInitialized else { return }
        
        // Stop monitoring
        stopStatusMonitoring()
        
        // Clear current user data
        currentUserPubkey = nil
        userProjects = []
        projectStatuses = [:]
        onlineProjects = []
        projectLLMConfigs = [:]
        projectConversations = [:]
        
        // Logout from auth manager
        authManager?.logout()
    }
}

