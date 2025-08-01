import SwiftUI
import NDKSwift

struct LessonDetailView: View {
    let lesson: NDKLesson
    let agent: NDKProjectStatus.AgentStatus
    
    @Environment(NostrManager.self) var nostrManager
    @State private var comments: [NDKEvent] = []
    @State private var newComment = ""
    @State private var commentSubscription: Task<Void, Never>?
    @FocusState private var isCommentFieldFocused: Bool
    @State private var isLoading = false
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Lesson Header
                    VStack(alignment: .leading, spacing: 16) {
                        Text(lesson.title)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        HStack {
                            Label(agent.name, systemImage: "person.circle")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(lesson.createdAt, style: .relative)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let lessonType = lesson.lessonType {
                            Label(lessonType, systemImage: "tag")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                    
                    Divider()
                    
                    // Lesson Content
                    Text(lesson.content)
                        .font(.body)
                        .padding()
                        .textSelection(.enabled)
                    
                    Divider()
                    
                    // Comments Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Comments")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        if comments.isEmpty {
                            Text("No comments yet. Be the first to comment!")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(comments, id: \.id) { comment in
                                CommentView(comment: comment)
                                    .id(comment.id)
                            }
                        }
                    }
                    .padding(.vertical)
                    
                    Spacer(minLength: 100) // Space for keyboard
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: comments.count) { _, newCount in
                if let lastComment = comments.last {
                    withAnimation {
                        proxy.scrollTo(lastComment.id, anchor: .bottom)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            // Comment Input Bar
            HStack(spacing: 12) {
                TextField("Add a comment...", text: $newComment, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(20)
                    .focused($isCommentFieldFocused)
                
                Button(action: sendComment) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(newComment.isEmpty ? .gray : .blue)
                    }
                }
                .disabled(newComment.isEmpty || isLoading)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .task {
            await subscribeToComments()
        }
        .onDisappear {
            commentSubscription?.cancel()
        }
    }
    
    private func sendComment() {
        guard !newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let content = newComment
        newComment = ""
        isLoading = true
        
        Task {
            do {
                _ = try await nostrManager.replyToLesson(
                    lesson,
                    content: content,
                    agentPubkey: agent.id
                )
                isLoading = false
            } catch {
                print("Failed to send comment: \(error)")
                // Restore the comment on failure
                newComment = content
                isLoading = false
            }
        }
    }
    
    private func subscribeToComments() async {
        commentSubscription?.cancel()
        
        commentSubscription = Task {
            // Subscribe to comments on this lesson
            let filter = NDKFilter(
                kinds: [TENEXEventKind.threadReply],
                tags: ["E": [lesson.id]]
            )
            
            let commentDataSource = nostrManager.ndk.subscribe(
                filter: filter,
                cachePolicy: .cacheWithNetwork
            )
            
            for await event in commentDataSource.events {
                if Task.isCancelled { break }
                
                await MainActor.run {
                    // Insert comment in chronological order
                    let insertIndex = comments.firstIndex { $0.createdAt > event.createdAt } ?? comments.count
                    if !comments.contains(where: { $0.id == event.id }) {
                        comments.insert(event, at: insertIndex)
                    }
                }
            }
        }
    }
}

struct CommentView: View {
    let comment: NDKEvent
    @Environment(NostrManager.self) var nostrManager
    
    var authorName: String {
        // Check if it's the current user
        if comment.pubkey == nostrManager.currentUserPubkey {
            return "You"
        }
        
        // Check if it's a known agent
        if let agent = nostrManager.projectStatuses.values
            .flatMap({ $0.availableAgents })
            .first(where: { $0.id == comment.pubkey }) {
            return agent.name
        }
        
        // Return shortened pubkey
        return String(comment.pubkey.prefix(8)) + "..."
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(authorName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(Date(timeIntervalSince1970: TimeInterval(comment.createdAt)), style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(comment.content)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        LessonDetailView(
            lesson: NDKLesson(event: NDKEvent(
                id: "1",
                pubkey: "agent123",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: TENEXEventKind.agentLesson,
                tags: [["title", "Test Lesson"]],
                content: "{\"title\": \"Test Lesson\", \"content\": \"This is a test lesson content that would contain valuable information about a specific topic.\"}",
                sig: "fakesignature"
            )),
            agent: NDKProjectStatus.AgentStatus(
                id: "agent123",
                slug: "test-agent",
                name: "Test Agent",
                status: "active",
                lastSeen: Date()
            )
        )
        .environment(NostrManager())
    }
}