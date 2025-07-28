import SwiftUI
import NDKSwift

struct NewConversationView: View {
    let project: NDKProject
    
    @Environment(NostrManager.self) var nostrManager
    @Environment(\.dismiss) var dismiss
    
    @State private var title = ""
    @State private var content = ""
    @State private var selectedAgents: Set<String> = [] // agent pubkeys
    @State private var isCreating = false
    
    var availableAgents: [NDKProjectStatus.AgentStatus] {
        nostrManager.getAvailableAgents(for: project.addressableId)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Conversation Title (Optional)") {
                    TextField("Enter title", text: $title)
                }
                
                Section("Message") {
                    TextEditor(text: $content)
                        .frame(minHeight: 100)
                }
                
                if !availableAgents.isEmpty {
                    Section("Available Agents") {
                        ForEach(availableAgents, id: \.id) { agent in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(agent.slug)
                                        .font(.headline)
                                    Text(agent.id)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
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
                    }
                } else {
                    Section {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("No agents available")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createConversation()
                    }
                    .disabled(content.isEmpty || isCreating)
                }
            }
            .disabled(isCreating)
            .overlay {
                if isCreating {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView("Creating conversation...")
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(10)
                        }
                }
            }
        }
    }
    
    private func createConversation() {
        isCreating = true
        
        Task {
            do {
                // Content already contains user's message
                let finalContent = content
                
                _ = try await nostrManager.createConversation(
                    in: project,
                    title: title.isEmpty ? nil : title,
                    content: finalContent,
                    mentionedAgentPubkeys: Array(selectedAgents)
                )
                
                dismiss()
            } catch {
                print("Failed to create conversation: \(error)")
                isCreating = false
            }
        }
    }
}