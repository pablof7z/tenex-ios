import SwiftUI
import NDKSwift
import CryptoKit

struct ProjectTabView: View {
    let project: NDKProject
    @Environment(NostrManager.self) var nostrManager
    @State private var selectedTab = 0
    @State private var showNewConversation = false
    @State private var showVoiceOnlyConversation = false
    @State private var showConversationOptions = false
    @State private var hasRequestedProjectStart = false
    @State private var showVoiceRecordingForDocs = false
    
    @State private var conversations: [NDKConversation] = []
    @State private var conversationStreamTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 0) {
                TabButton(
                    title: "Threads",
                    count: conversations.count,
                    isSelected: selectedTab == 0,
                    action: { selectedTab = 0 }
                )
                
                TabButton(
                    title: "Docs",
                    count: 0, // Will be updated by ArticleListView
                    isSelected: selectedTab == 1,
                    action: { selectedTab = 1 }
                )
                
                TabButton(
                    title: "Agents",
                    count: {
                        let agents = nostrManager.getAvailableAgents(for: project.addressableId)
                        print("🎯 ProjectTabView: Agent count for \(project.addressableId): \(agents.count)")
                        return agents.count
                    }(),
                    isSelected: selectedTab == 2,
                    action: { selectedTab = 2 }
                )
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))
            
            Divider()
            
            // Tab content
            if selectedTab == 0 {
                ConversationTabContent(
                    project: project,
                    conversations: conversations,
                    showNewConversation: $showNewConversation
                )
            } else if selectedTab == 1 {
                ArticleListView(project: project)
            } else {
                // Agent list
                let agents = nostrManager.getAvailableAgents(for: project.addressableId)
                if agents.isEmpty {
                    ContentUnavailableView(
                        "No Agents Available",
                        systemImage: "person.3",
                        description: Text("Waiting for project to come online...")
                    )
                } else {
                    AgentListView(agents: agents)
                }
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedTab == 0 {
                    Button(action: {
                        showConversationOptions = true
                    }) {
                        Image(systemName: "plus")
                    }
                } else if selectedTab == 1 {
                    Button(action: {
                        showVoiceRecordingForDocs = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showNewConversation) {
            NewConversationView(
                project: project
            )
        }
        .fullScreenCover(isPresented: $showVoiceOnlyConversation) {
            VoiceRecordingView(project: project)
        }
        .confirmationDialog("Create New Conversation", isPresented: $showConversationOptions, titleVisibility: .visible) {
            Button("Text Conversation") {
                showNewConversation = true
            }
            
            Button("Voice Message") {
                showVoiceOnlyConversation = true
            }
            
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose how you want to start your conversation")
        }
        .task {
            // Start streaming data
            conversationStreamTask = Task {
                await streamConversations()
            }
            
            // Check initial project status
            await checkAndRequestProjectStart()
        }
        .onDisappear {
            conversationStreamTask?.cancel()
        }
    }
    
    private func streamConversations() async {
        let filter = NDKFilter(
            kinds: [NDKConversation.kind],
            tags: ["a": [project.addressableId]]
        )
        
        let conversationSource = nostrManager.ndk.observe(
            filter: filter,
            maxAge: 0,
            cachePolicy: .cacheWithNetwork
        )
        
        for await event in conversationSource.events {
            let conversation = NDKConversation(event: event)
            
            await MainActor.run {
                if !conversations.contains(where: { $0.id == conversation.id }) {
                    conversations.append(conversation)
                    // Sort by creation date, newest first
                    conversations.sort { $0.createdAt > $1.createdAt }
                }
            }
        }
    }
    
    private func checkAndRequestProjectStart() async {
        // Only request start once per session
        guard !hasRequestedProjectStart else { return }
        
        print("🚀 ProjectTabView: Checking project start for \(project.addressableId)")
        
        // Check if project is already online using centralized status
        let isOnline = nostrManager.isProjectOnline(project.addressableId)
        print("🚀 ProjectTabView: Project \(project.addressableId) is online: \(isOnline)")
        
        if !isOnline {
            print("🚀 ProjectTabView: Requesting project start for \(project.addressableId)")
            // Send ephemeral event to start the project
            await nostrManager.requestProjectStart(project: project)
            hasRequestedProjectStart = true
        }
    }
    
    private func createDocumentationRequest(
        transcript: String,
        audioURL: URL,
        duration: TimeInterval,
        waveformAmplitudes: [Float]
    ) async {
        do {
            // Format the content with the transcript
            let content = "Create a spec document with this. <transcript>\(transcript)</transcript>. This is a transcript, you might need to clean it up, format it, but don't change the essence of it."
            
            // Find project manager agent
            var mentionedAgents: [String] = []
            let projectManagerAgent = nostrManager.getAvailableAgents(for: project.addressableId)
                .first { $0.slug == "project-manager" }
            
            if let projectManager = projectManagerAgent {
                mentionedAgents.append(projectManager.id)
            }
            
            // Create new conversation
            let conversation = try await nostrManager.createConversation(
                in: project,
                title: nil,
                content: content,
                mentionedAgentPubkeys: mentionedAgents
            )
            
            // Upload audio and create audio event
            try await uploadAudioAndCreateEvent(
                audioURL: audioURL,
                conversation: conversation,
                transcription: transcript,
                duration: duration,
                waveformAmplitudes: waveformAmplitudes,
                mentionedAgentPubkeys: mentionedAgents
            )
        } catch {
            print("Failed to create documentation request: \(error)")
        }
    }
    
    private func uploadAudioAndCreateEvent(
        audioURL: URL,
        conversation: NDKConversation,
        transcription: String,
        duration: TimeInterval,
        waveformAmplitudes: [Float],
        mentionedAgentPubkeys: [String]
    ) async throws {
        // Read audio data from file
        let audioData = try Data(contentsOf: audioURL)
        
        // Upload audio file to blossom server using BlossomClient
        let blossomClient = BlossomClient()
        let uploadResult = try await blossomClient.uploadWithAuth(
            data: audioData,
            mimeType: "audio/m4a",
            to: "https://blossom.primal.net",
            signer: nostrManager.ndk.signer!,
            ndk: nostrManager.ndk
        )
        
        let blossomURL = URL(string: uploadResult.url)!
        
        // Create waveform data for imeta tag
        let waveformString = waveformAmplitudes
            .map { String(format: "%.2f", $0) }
            .joined(separator: " ")
        
        // Create audio event per NIP-94 (kind 1063 for file metadata)
        var builder = NDKEventBuilder(ndk: nostrManager.ndk)
            .content(transcription) // NIP-94 uses content for description
            .kind(1063) // NIP-94 file metadata event
            .tag(["url", blossomURL.absoluteString])
            .tag(["m", "audio/m4a"]) // MIME type
            .tag(["x", calculateSHA256(of: audioData)]) // File hash
            .tag(["size", String(audioData.count)]) // File size in bytes
            .tag(["e", conversation.id]) // Reference the conversation
            .tag(["a", project.addressableId]) // Reference the project
        
        // Add optional tags
        if !waveformString.isEmpty {
            builder = builder
                .tag(["waveform", waveformString])
                .tag(["duration", String(Int(duration))])
        }
        
        // Add agent mentions using p tags
        for agentPubkey in mentionedAgentPubkeys {
            builder = builder.tag(["p", agentPubkey])
        }
        
        let audioEvent = try await builder.build()
        try await nostrManager.ndk.publish(audioEvent)
    }
    
    private func calculateSHA256(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

struct TabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                    
                    Text("(\(count))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                .foregroundColor(isSelected ? .blue : .gray)
                
                Rectangle()
                    .fill(isSelected ? Color.blue : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ConversationTabContent: View {
    let project: NDKProject
    let conversations: [NDKConversation]
    @Binding var showNewConversation: Bool
    
    var body: some View {
        if conversations.isEmpty {
            ContentUnavailableView(
                "No Conversations",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Start a new conversation in this project")
            )
        } else {
            List {
                ForEach(conversations) { conversation in
                    NavigationLink(destination: ConversationDetailView(
                        conversation: conversation,
                        project: project
                    )) {
                        ConversationRowView(conversation: conversation, currentPhase: nil)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            .listStyle(.plain)
        }
    }
}