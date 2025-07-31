import SwiftUI
import NDKSwift

struct CreateProjectView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(NostrManager.self) var nostrManager
    
    @State private var projectName = ""
    @State private var projectDescription = ""
    @State private var hashtags = ""
    @State private var repoUrl = ""
    @State private var imageUrl = ""
    @State private var selectedAgents: [NDKAgent] = []
    @State private var isCreating = false
    @State private var showAgentSelector = false
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, description, hashtags, repo, image
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Project Details") {
                    TextField("Project Name", text: $projectName)
                        .focused($focusedField, equals: .name)
                        .autocorrectionDisabled()
                    
                    TextField("Description", text: $projectDescription, axis: .vertical)
                        .focused($focusedField, equals: .description)
                        .lineLimit(3...6)
                    
                    TextField("Hashtags (comma separated)", text: $hashtags)
                        .focused($focusedField, equals: .hashtags)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                
                Section("Additional Information") {
                    TextField("Repository URL", text: $repoUrl)
                        .focused($focusedField, equals: .repo)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    
                    TextField("Logo Image URL", text: $imageUrl)
                        .focused($focusedField, equals: .image)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                
                Section("AI Agents") {
                    Button(action: { showAgentSelector = true }) {
                        HStack {
                            Text("Select Agents")
                            Spacer()
                            if !selectedAgents.isEmpty {
                                Text("\(selectedAgents.count) selected")
                                    .foregroundColor(.gray)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    if !selectedAgents.isEmpty {
                        ForEach(selectedAgents, id: \.id) { agent in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(agent.name)
                                        .font(.system(size: 15, weight: .medium))
                                    if let role = agent.role {
                                        Text(role)
                                            .font(.system(size: 13))
                                            .foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createProject()
                    }
                    .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
            .disabled(isCreating)
            .sheet(isPresented: $showAgentSelector) {
                AgentSelectorView(selectedAgents: $selectedAgents)
            }
        }
    }
    
    private func createProject() {
        guard !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isCreating = true
        focusedField = nil
        
        Task {
            await createProjectEvent()
        }
    }
    
    @MainActor
    private func createProjectEvent() async {
        guard let signer = nostrManager.ndk.signer else {
            print("No signer available")
            isCreating = false
            return
        }
        
        // Set d tag with a unique identifier
        let identifier = UUID().uuidString.lowercased()
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Build event using builder pattern
        var builder = NDKEventBuilder(ndk: nostrManager.ndk)
            .kind(TENEXEventKind.project)
            .content(projectDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "A new TENEX project: \(trimmedName)"
                : projectDescription.trimmingCharacters(in: .whitespacesAndNewlines))
            .tag(["d", identifier])
            .tag(["title", trimmedName])
        
        // Add hashtags
        if !hashtags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let hashtagArray = hashtags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            if !hashtagArray.isEmpty {
                builder = builder.tag(["hashtags"] + hashtagArray)
            }
        }
        
        // Add repo URL
        if !repoUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            builder = builder.tag(["repo", repoUrl.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        
        // Add image URL
        if !imageUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            builder = builder.tag(["picture", imageUrl.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        
        // Add selected agents
        for agent in selectedAgents {
            builder = builder.tag(["agent", agent.id])
        }
        
        do {
            // Build and sign the event
            let event = try await builder.build(signer: signer)
            
            print("Publishing project event with kind: \(event.kind), d-tag: \(identifier)")
            print("Event ID: \(event.id)")
            print("Tags: \(event.tags)")
            
            // Publish to relays
            let publishedRelays = try await nostrManager.ndk.publish(event)
            print("Published to \(publishedRelays.count) relays")
            
            // Create local NDKProject instance to add to NostrManager
            let ndkProject = NDKProject(event: event)
            
            // Add to NostrManager's projects
            await MainActor.run {
                nostrManager.addProject(ndkProject)
                dismiss()
            }
        } catch {
            print("Failed to create/publish project event: \(error)")
            isCreating = false
        }
    }
}

#Preview {
    CreateProjectView()
        .environment(NostrManager())
}