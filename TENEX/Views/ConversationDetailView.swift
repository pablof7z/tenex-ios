import SwiftUI
import NDKSwift

struct ConversationDetailView: View {
    let conversation: NDKConversation
    let project: NDKProject
    
    @Environment(NostrManager.self) var nostrManager
    @StateObject private var audioManager = AudioManager.shared
    @State private var messageText = ""
    @State private var replies: [NDKEvent] = []
    @State private var tasks: [NDKTask] = []
    @State private var audioEvents: [NDKEvent] = [] // Audio events (kind 1063 with audio MIME types)
    @State private var typingIndicators: [String: NDKTypingIndicator] = [:] // conversationId -> indicator
    @State private var showAgentPicker = false
    @State private var selectedAgents: Set<String> = []
    @State private var selectedTask: NDKTask?
    @State private var isVoiceCallActive = false
    
    @State private var replySubscription: Task<Void, Never>?
    @State private var typingSubscription: Task<Void, Never>?
    @State private var taskSubscription: Task<Void, Never>?
    
    // Get available agents for the project
    private var availableAgents: [NDKProjectStatus.AgentStatus] {
        nostrManager.getAvailableAgents(for: project.addressableId)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // Original conversation
                        ConversationMessageView(
                            content: conversation.content,
                            author: conversation.author,
                            timestamp: conversation.createdAt,
                            isFromCurrentUser: conversation.author == nostrManager.currentUserPubkey,
                            availableAgents: availableAgents,
                            messageId: conversation.id,
                            onTTSPressed: {
                                handleTTSPressed(for: conversation.id)
                            },
                            isCurrentlyPlayingTTS: audioManager.currentTTSMessageId == conversation.id && audioManager.isTTSPlaying
                        )
                        .id(conversation.id)
                        
                        // Replies, tasks, and audio events in chronological order
                        let allEvents = (replies + tasks.map { $0.event } + audioEvents).sorted { $0.createdAt < $1.createdAt }
                        
                        ForEach(allEvents, id: \.id) { event in
                            if event.kind == TENEXEventKind.task {
                                // Render task card
                                if let task = tasks.first(where: { $0.id == event.id }) {
                                    TaskCardView(
                                        task: task,
                                        project: project,
                                        onTap: {
                                            selectedTask = task
                                        }
                                    )
                                    .padding(.horizontal)
                                    .id(event.id)
                                }
                            } else if event.kind == 1063 && isAudioEvent(event) {
                                // Render voice message
                                VoiceMessageView(
                                    audioEvent: event,
                                    isFromCurrentUser: event.pubkey == nostrManager.currentUserPubkey,
                                    availableAgents: availableAgents
                                )
                                .environmentObject(audioManager)
                                .id(event.id)
                            } else {
                                // Render regular message
                                ConversationMessageView(
                                    content: event.content,
                                    author: event.pubkey,
                                    timestamp: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
                                    isFromCurrentUser: event.pubkey == nostrManager.currentUserPubkey,
                                    mentionedAgents: event.tags
                                        .filter { $0.first == "p" }
                                        .compactMap { $0.count > 1 ? String($0[1]) : nil },
                                    availableAgents: availableAgents,
                                    messageId: event.id,
                                    onTTSPressed: {
                                        handleTTSPressed(for: event.id)
                                    },
                                    isCurrentlyPlayingTTS: audioManager.currentTTSMessageId == event.id && audioManager.isTTSPlaying
                                )
                                .id(event.id)
                            }
                        }
                        
                        // Typing indicators
                        ForEach(Array(typingIndicators.values), id: \.conversationId) { indicator in
                            TypingIndicatorView(message: indicator.message)
                        }
                    }
                    .padding()
                }
                .onChange(of: replies.count + audioEvents.count) {
                    withAnimation {
                        // Scroll to the last event (could be reply or audio)
                        let allEvents = (replies + audioEvents).sorted { $0.createdAt < $1.createdAt }
                        proxy.scrollTo(allEvents.last?.id, anchor: .bottom)
                    }
                }
            }
            
            // Selected agents bar
            if !selectedAgents.isEmpty {
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(selectedAgents), id: \.self) { agentPubkey in
                                HStack(spacing: 4) {
                                    Text("@\(String(agentPubkey.prefix(8))...)")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Button(action: {
                                        selectedAgents.remove(agentPubkey)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 4)
                .background(Color(.systemBackground))
            }
            
            Divider()
            
            // Input area
            HStack(spacing: 12) {
                Button(action: {
                    showAgentPicker = true
                }) {
                    Image(systemName: "at")
                        .font(.system(size: 22))
                        .foregroundColor(.gray)
                }
                
                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(20)
                
                if messageText.isEmpty {
                    Button(action: {
                        isVoiceCallActive = true
                    }) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.blue)
                    }
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isVoiceCallActive) {
            VoiceOnlyConversationView(
                project: project,
                replyToConversation: conversation,
                lastVisibleMessage: replies.last ?? conversation.event
            )
        }
        .task {
            // Subscribe to replies reactively
            replySubscription = Task {
                await subscribeToReplies()
            }
            
            // Subscribe to typing indicators reactively
            typingSubscription = Task {
                await subscribeToTyping()
            }
            
            // Subscribe to tasks reactively
            taskSubscription = Task {
                await subscribeToTasks()
            }
            
            // Subscribe to audio events reactively
            await subscribeToAudioEvents()
        }
        .onDisappear {
            // Clean up subscriptions
            replySubscription?.cancel()
            typingSubscription?.cancel()
            taskSubscription?.cancel()
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task, project: project)
        }
    }
    
    private func handleTTSPressed(for messageId: String) {
        Task {
            // Check if we should start or stop TTS
            let shouldStart = audioManager.toggleMessageTTS(for: messageId)
            
            if shouldStart {
                // Prepare all messages for TTS
                var allMessages: [(id: String, content: String, author: String?)] = []
                
                // Add original conversation
                allMessages.append((
                    id: conversation.id,
                    content: conversation.content,
                    author: conversation.author
                ))
                
                // Add all replies and regular messages (not tasks or audio)
                let allEvents = (replies + audioEvents).sorted { $0.createdAt < $1.createdAt }
                for event in allEvents {
                    if event.kind != TENEXEventKind.task && !(event.kind == 1063 && isAudioEvent(event)) {
                        allMessages.append((
                            id: event.id,
                            content: event.content,
                            author: event.pubkey
                        ))
                    }
                }
                
                // Start TTS from the selected message
                await audioManager.startMessageTTS(messages: allMessages, startingFromId: messageId)
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let content = messageText
        
        // Get the last visible message (last reply or the original conversation)
        let lastVisibleMessage = replies.last ?? conversation.event
        
        Task {
            do {
                // Add agent mentions to content
                // Content already includes mentions from UI
                let finalContent = content
                
                _ = try await nostrManager.replyToConversation(
                    conversation,
                    content: finalContent,
                    mentionedAgentPubkeys: Array(selectedAgents),
                    lastVisibleMessage: lastVisibleMessage
                )
                
                messageText = ""
                selectedAgents.removeAll()
            } catch {
                print("Failed to send message: \(error)")
            }
        }
    }
    
    private func subscribeToReplies() async {
        // Use NDKSwift's reactive observation for thread replies
        let filter = NDKFilter(
            kinds: [TENEXEventKind.threadReply],
            tags: ["e": [conversation.id]]
        )
        
        let replyDataSource = nostrManager.ndk.observe(
            filter: filter,
            cachePolicy: .cacheWithNetwork
        )
        
        // Stream replies reactively
        for await event in replyDataSource.events {
            // Insert reply in chronological order
            let insertIndex = replies.firstIndex { $0.createdAt > event.createdAt } ?? replies.count
            replies.insert(event, at: insertIndex)
        }
    }
    
    private func subscribeToTyping() async {
        // Use reactive typing indicator subscription
        let filter = NDKFilter(
            kinds: [NDKTypingIndicator.kind],
            tags: ["e": [conversation.id]]
        )
        
        let typingDataSource = nostrManager.ndk.observe(
            filter: filter,
            cachePolicy: .networkOnly // Ephemeral events, don't cache
        )
        
        // Stream typing indicators reactively
        for await event in typingDataSource.events {
            let indicator = NDKTypingIndicator(event: event)
            
            if indicator.isValid {
                typingIndicators[indicator.conversationId] = indicator
                
                // Auto-remove after expiration
                Task {
                    try? await Task.sleep(nanoseconds: 61_000_000_000) // 61 seconds
                    typingIndicators.removeValue(forKey: indicator.conversationId)
                }
            }
        }
    }
}

struct ConversationMessageView: View {
    let content: String
    let author: String
    let timestamp: Date
    let isFromCurrentUser: Bool
    var mentionedAgents: [String] = []
    var availableAgents: [NDKProjectStatus.AgentStatus] = []
    let messageId: String
    let onTTSPressed: () -> Void
    let isCurrentlyPlayingTTS: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Show avatar for all non-current-user messages
            if !isFromCurrentUser {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(author.prefix(2)).uppercased())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    )
            }
            
            if isFromCurrentUser {
                Spacer()
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                if !mentionedAgents.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(mentionedAgents, id: \.self) { agent in
                            Text("@\(agent)")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                HStack(spacing: 4) {
                    Text(content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isFromCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(isFromCurrentUser ? .white : .primary)
                        .cornerRadius(16)
                    
                    // TTS button
                    Button(action: onTTSPressed) {
                        Image(systemName: isCurrentlyPlayingTTS ? "speaker.wave.3.fill" : "speaker.wave.1.fill")
                            .font(.system(size: 16))
                            .foregroundColor(isCurrentlyPlayingTTS ? .blue : .gray)
                            .padding(6)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                
                Text(timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: isFromCurrentUser ? .trailing : .leading)
            
            if !isFromCurrentUser {
                Spacer()
            }
        }
    }
}

struct TypingIndicatorView: View {
    let message: String
    @State private var animationPhase = 0
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 8, height: 8)
                            .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(16)
            }
            
            Spacer()
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 0.6).repeatForever()) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

struct AgentPickerView: View {
    let availableAgents: [NDKAgent]
    @Binding var selectedAgents: Set<String>
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List(availableAgents, id: \.id) { agent in
                HStack {
                    VStack(alignment: .leading) {
                        Text(agent.name)
                            .font(.headline)
                        if let description = agent.description {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    if selectedAgents.contains(agent.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedAgents.contains(agent.id) {
                        selectedAgents.remove(agent.id)
                    } else {
                        selectedAgents.insert(agent.id)
                    }
                }
            }
            .navigationTitle("Select Agents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Extension to add subscribeToTasks function
extension ConversationDetailView {
    
    private func subscribeToTasks() async {
        // Subscribe to tasks in this conversation
        let filter = NDKFilter(
            kinds: [TENEXEventKind.task],
            tags: ["e": [conversation.id]]
        )
        
        let taskDataSource = nostrManager.ndk.observe(
            filter: filter,
            cachePolicy: .cacheWithNetwork
        )
        
        // Stream tasks reactively
        for await event in taskDataSource.events {
            let task = NDKTask(event: event)
            
            // Check if we already have this task
            if let existingIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                // Update existing task
                tasks[existingIndex].update(from: event)
            } else {
                // Add new task
                tasks.append(task)
            }
        }
    }
    
    private func subscribeToAudioEvents() async {
        // Subscribe to NIP-94 file metadata events for this conversation
        let filter = NDKFilter(
            kinds: [1063], // NIP-94 file metadata events
            tags: ["e": [conversation.id]]
        )
        
        let audioDataSource = nostrManager.ndk.observe(
            filter: filter,
            cachePolicy: .cacheWithNetwork
        )
        
        // Stream audio events reactively
        for await event in audioDataSource.events {
            // Only process events with audio MIME types
            if isAudioEvent(event) {
                // Insert audio event in chronological order
                let insertIndex = audioEvents.firstIndex { $0.createdAt > event.createdAt } ?? audioEvents.count
                audioEvents.insert(event, at: insertIndex)
                
                // Extract URL from tags and start downloading the audio for faster playback
                if let audioUrl = getAudioURL(from: event) {
                    Task {
                        await audioManager.preloadAudio(from: audioUrl)
                    }
                }
            }
        }
    }
    
    private func isAudioEvent(_ event: NDKEvent) -> Bool {
        // Check if the event has an audio MIME type in the "m" tag
        guard let mimeType = event.tags.first(where: { $0.first == "m" && $0.count > 1 })?[1] else {
            return false
        }
        return mimeType.hasPrefix("audio/")
    }
    
    private func getAudioURL(from event: NDKEvent) -> String? {
        // Extract URL from the "url" tag
        return event.tags.first(where: { $0.first == "url" && $0.count > 1 })?[1]
    }
}

// Task detail view with reply functionality
struct TaskDetailView: View {
    let task: NDKTask
    let project: NDKProject
    @Environment(\.dismiss) var dismiss
    @Environment(NostrManager.self) var nostrManager
    @State private var statusUpdates: [NDKEvent] = []
    @State private var updateSubscription: Task<Void, Never>?
    @State private var messageText = ""
    @State private var claudeSessionId: String?
    @State private var mostRecentNonUserUpdate: NDKEvent?
    @State private var showAgentPicker = false
    @State private var selectedAgents: Set<String> = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Task header
                            TaskCardView(task: task, project: project)
                                .padding(.horizontal)
                            
                            Divider()
                            
                            // Status updates
                            if !statusUpdates.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Status Updates")
                                        .font(.headline)
                                        .padding(.horizontal)
                                    
                                    ForEach(statusUpdates, id: \.id) { update in
                                        TaskStatusUpdateView(update: update)
                                            .padding(.horizontal)
                                            .id(update.id)
                                    }
                                }
                            } else {
                                Text("No status updates yet")
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
                        }
                        .padding(.bottom, 100) // Space for input area
                    }
                    .onChange(of: statusUpdates.count) {
                        withAnimation {
                            proxy.scrollTo(statusUpdates.last?.id, anchor: .bottom)
                        }
                    }
                }
                
                Spacer()
                
                // Selected agents bar
                if !selectedAgents.isEmpty {
                    HStack {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Array(selectedAgents), id: \.self) { agentPubkey in
                                    HStack(spacing: 4) {
                                        Text("@\(String(agentPubkey.prefix(8))...)")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                        Button(action: {
                                            selectedAgents.remove(agentPubkey)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 4)
                    .background(Color(.systemBackground))
                }
                
                Divider()
                
                // Input area
                HStack(spacing: 12) {
                    Button(action: {
                        showAgentPicker = true
                    }) {
                        Image(systemName: "at")
                            .font(.system(size: 22))
                            .foregroundColor(.gray)
                    }
                    
                    TextField("Reply to task...", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(20)
                    
                    Button(action: sendReply) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(messageText.isEmpty ? .gray : .blue)
                    }
                    .disabled(messageText.isEmpty || claudeSessionId == nil)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            updateSubscription = Task {
                await subscribeToTaskUpdates()
            }
        }
        .onDisappear {
            updateSubscription?.cancel()
        }
    }
    
    private func sendReply() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let claudeSessionId = claudeSessionId else { return }
        
        let content = messageText
        
        Task {
            do {
                // Create a reply to the task using task's replyBuilder
                let replyBuilder = task.replyBuilder(ndk: nostrManager.ndk)
                    .content(content)
                
                // Build the event first to get the auto-generated tags
                let preliminaryEvent = try await replyBuilder.build()
                
                // Create new tags array, filtering out any p-tags added by reply()
                var newTags = preliminaryEvent.tags.filter { $0[0] != "p" }
                
                // Add project reference
                newTags.append(["a", project.addressableId])
                
                // Add mentioned agents or most recent responder
                if !selectedAgents.isEmpty {
                    // Add explicitly mentioned agents
                    for agentPubkey in selectedAgents {
                        newTags.append(["p", agentPubkey])
                    }
                } else if let mostRecentUpdate = mostRecentNonUserUpdate {
                    // P-tag the most recent non-user update
                    newTags.append(["p", mostRecentUpdate.pubkey])
                }
                
                // Add claude-session tag for routing
                newTags.append(["claude-session", claudeSessionId])
                
                // Create final event with cleaned up tags
                let finalEvent = NDKEvent(
                    id: preliminaryEvent.id,
                    pubkey: preliminaryEvent.pubkey,
                    createdAt: preliminaryEvent.createdAt,
                    kind: preliminaryEvent.kind,
                    tags: newTags,
                    content: preliminaryEvent.content,
                    sig: ""  // Will be signed when published
                )
                
                // Sign and publish
                try await nostrManager.ndk.publish(finalEvent)
                
                // Clear input
                messageText = ""
                selectedAgents.removeAll()
            } catch {
                print("Failed to send reply: \(error)")
            }
        }
    }
    
    private func subscribeToTaskUpdates() async {
        // Subscribe to status updates for this task
        let filter = NDKFilter(
            kinds: [EventKind.genericReply],
            tags: ["e": [task.id]]
        )
        
        let updateDataSource = nostrManager.ndk.observe(
            filter: filter,
            cachePolicy: .cacheWithNetwork
        )
        
        // Stream updates reactively
        for await event in updateDataSource.events {
            // Insert update in chronological order
            let insertIndex = statusUpdates.firstIndex { $0.createdAt > event.createdAt } ?? statusUpdates.count
            statusUpdates.insert(event, at: insertIndex)
            
            // Track most recent non-user update
            if event.pubkey != nostrManager.currentUserPubkey {
                mostRecentNonUserUpdate = event
            }
            
            // Extract claude-session from real status updates (not task descriptions)
            let isTaskDescription = event.tags.contains { $0[0] == "task-description" }
            if !isTaskDescription {
                if let sessionTag = event.tags.first(where: { $0[0] == "claude-session" }),
                   sessionTag.count > 1 {
                    claudeSessionId = sessionTag[1]
                }
            }
        }
    }
    
}