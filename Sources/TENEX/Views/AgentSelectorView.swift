import SwiftUI
import NDKSwift

struct AgentSelectorView: View {
    @Binding var selectedAgents: [NDKAgent]
    @Environment(\.dismiss) var dismiss
    @Environment(NostrManager.self) var nostrManager
    
    @State private var availableAgents: [NDKAgent] = []
    @State private var searchText = ""
    @State private var isLoading = true
    
    var filteredAgents: [NDKAgent] {
        if searchText.isEmpty {
            return availableAgents
        }
        
        let searchLower = searchText.lowercased()
        return availableAgents.filter { agent in
            agent.name.lowercased().contains(searchLower) ||
            (agent.description?.lowercased().contains(searchLower) ?? false) ||
            (agent.role?.lowercased().contains(searchLower) ?? false)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading agents...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if availableAgents.isEmpty {
                    ContentUnavailableView(
                        "No Agents Available",
                        systemImage: "person.crop.circle",
                        description: Text("No AI agents have been published yet")
                    )
                } else {
                    List {
                        ForEach(filteredAgents, id: \.id) { agent in
                            AgentRow(
                                agent: agent,
                                isSelected: selectedAgents.contains(where: { $0.id == agent.id }),
                                onToggle: { toggleAgent(agent) }
                            )
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search agents")
                }
            }
            .navigationTitle("Select Agents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
            .task {
                await loadAgents()
            }
        }
    }
    
    private func toggleAgent(_ agent: NDKAgent) {
        if let index = selectedAgents.firstIndex(where: { $0.id == agent.id }) {
            selectedAgents.remove(at: index)
        } else {
            selectedAgents.append(agent)
        }
    }
    
    private func loadAgents() async {
        isLoading = true
        
        let filter = NDKFilter(
            kinds: [NDKAgent.kind],
            limit: 100
        )
        
        let source = nostrManager.ndk.subscribe(
            filter: filter,
            cachePolicy: .cacheWithNetwork
        )
        
        var agents: [NDKAgent] = []
        
        for await event in source.events {
            let agent = NDKAgent(event: event)
            
            // Avoid duplicates
            if !agents.contains(where: { $0.id == agent.id }) {
                agents.append(agent)
            }
            
            // Update UI periodically
            if agents.count % 10 == 0 {
                await MainActor.run {
                    availableAgents = agents.sorted { $0.name < $1.name }
                }
            }
        }
        
        // Final update
        await MainActor.run {
            availableAgents = agents.sorted { $0.name < $1.name }
            isLoading = false
        }
    }
}

struct AgentRow: View {
    let agent: NDKAgent
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.system(size: 24))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    if let role = agent.role {
                        Text(role)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    
                    if let description = agent.description {
                        Text(description)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    if !agent.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(agent.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                            }
                            
                            if agent.tags.count > 3 {
                                Text("+\(agent.tags.count - 3)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AgentSelectorView(selectedAgents: .constant([]))
        .environment(NostrManager())
}