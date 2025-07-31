import SwiftUI
import NDKSwift

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
        .fullScreenCover(isPresented: $showVoiceRecordingForDocs) {
            DocumentationRecordingView(
                project: project,
                onDocumentationCreated: {
                    showVoiceRecordingForDocs = false
                }
            )
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
        
        let conversationSource = nostrManager.ndk.subscribe(
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