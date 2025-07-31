import SwiftUI
import NDKSwift

struct ConversationListView: View {
    let project: NDKProject
    @Environment(NostrManager.self) var nostrManager
    @State private var showNewConversation = false
    @State private var showVoiceOnlyConversation = false
    @State private var showConversationOptions = false
    
    @State private var conversations: [NDKConversation] = []
    @State private var conversationPhases: [String: String] = [:] // conversationId -> phase
    
    @State private var conversationStreamTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            if conversations.isEmpty {
                ContentUnavailableView(
                    "No Conversations",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start a conversation to collaborate with AI agents")
                )
            } else {
                List(conversations) { conversation in
                    NavigationLink(destination: ConversationDetailView(conversation: conversation, project: project)) {
                        ConversationRowView(
                            conversation: conversation,
                            currentPhase: conversationPhases[conversation.id]
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Conversations")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showConversationOptions = true
                }) {
                    Image(systemName: "plus")
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
            // Start streaming conversations and agents
            conversationStreamTask = Task {
                await streamConversations()
            }
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
        
        let conversationSource = nostrManager.ndk.subscribe(
            filter: filter,
            maxAge: 300,
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
            
            // Stream status updates for this conversation
            Task {
                await streamConversationStatus(conversationId: conversation.id)
            }
        }
    }
    
    private func streamConversationStatus(conversationId: String) async {
        let filter = NDKFilter(
            kinds: [1111], // Status update kind
            tags: ["e": [conversationId]]
        )
        
        let statusSource = nostrManager.ndk.subscribe(
            filter: filter,
            maxAge: 0,
            cachePolicy: .cacheWithNetwork
        )
        
        for await event in statusSource.events {
            // Look for phase tag
            if let phase = event.tags.first(where: { $0.first == "phase" })?.dropFirst().first ??
                           event.tags.first(where: { $0.first == "new-phase" })?.dropFirst().first {
                await MainActor.run {
                    conversationPhases[conversationId] = phase
                }
            }
        }
    }
    
}

struct ConversationRowView: View {
    let conversation: NDKConversation
    let currentPhase: String?
    @Environment(NostrManager.self) var nostrManager
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Phase icon
            PhaseIconView(phase: currentPhase, size: 16)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(conversation.title)
                        .font(.system(size: 17, weight: .medium))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(conversation.createdAt, style: .relative)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Text(conversation.content)
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
                    .lineLimit(2)
                
                if conversation.replyCount > 0 {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Text("\(conversation.replyCount) replies")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}