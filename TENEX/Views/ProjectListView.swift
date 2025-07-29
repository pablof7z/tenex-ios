import SwiftUI
import NDKSwift

struct ProjectListView: View {
    @Environment(NostrManager.self) var nostrManager
    @State private var searchText = ""
    @State private var conversationCounts: [String: Int] = [:] // projectId -> count
    @State private var lastActivityDates: [String: Date] = [:] // projectId -> date
    
    var filteredAndSortedProjects: [NDKProject] {
        // Get projects from NostrManager (single source of truth)
        let projects = nostrManager.projects
        
        // Filter by search
        let filtered = searchText.isEmpty ? projects : projects.filter { project in
            project.name.localizedCaseInsensitiveContains(searchText)
        }
        
        // Sort by most recent activity
        return filtered.sorted { project1, project2 in
            let date1 = lastActivityDates[project1.addressableId] ?? Date.distantPast
            let date2 = lastActivityDates[project2.addressableId] ?? Date.distantPast
            return date1 > date2
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredAndSortedProjects.isEmpty && nostrManager.isAuthenticated {
                    ContentUnavailableView(
                        "No Projects",
                        systemImage: "folder",
                        description: Text("Create a project to get started")
                    )
                } else {
                    List {
                        ForEach(filteredAndSortedProjects, id: \.id) { project in
                            NavigationLink(destination: ProjectTabView(project: project)) {
                                ProjectRowView(
                                    project: project,
                                    conversationCount: conversationCounts[project.addressableId] ?? 0,
                                    lastActivity: lastActivityDates[project.addressableId]
                                )
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Search projects")
            .navigationTitle("TENEX")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // TODO: Add new project creation with optimistic publishing
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                // Stream conversations for existing projects
                for project in nostrManager.projects {
                    Task {
                        await streamConversations(for: project)
                    }
                }
            }
        }
    }
    
    
    private func streamConversations(for project: NDKProject) async {
        let conversationFilter = NDKFilter(
            kinds: [NDKConversation.kind],
            tags: ["a": [project.addressableId]]
        )
        
        let conversationSource = nostrManager.ndk.observe(
            filter: conversationFilter,
            maxAge: 300,
            cachePolicy: .cacheWithNetwork
        )
        
        var projectConversations: [NDKConversation] = []
        
        for await event in conversationSource.events {
            let conversation = NDKConversation(event: event)
            
            if !projectConversations.contains(where: { $0.id == conversation.id }) {
                projectConversations.append(conversation)
                
                await MainActor.run {
                    // Update conversation count - create new dictionary to trigger UI update
                    var updatedCounts = conversationCounts
                    updatedCounts[project.addressableId] = projectConversations.count
                    conversationCounts = updatedCounts
                    
                    // Update last activity date - create new dictionary to trigger UI update
                    let mostRecentDate = projectConversations
                        .map { $0.createdAt }
                        .max() ?? Date.distantPast
                    var updatedDates = lastActivityDates
                    updatedDates[project.addressableId] = mostRecentDate
                    lastActivityDates = updatedDates
                }
            }
        }
    }
}

struct ProjectRowView: View {
    let project: NDKProject
    let conversationCount: Int
    let lastActivity: Date?
    @Environment(NostrManager.self) var nostrManager
    
    var availableAgents: Int {
        let agents = nostrManager.getAvailableAgents(for: project.addressableId)
        print("🎯 ProjectRowView: Agent count for \(project.addressableId): \(agents.count)")
        return agents.count
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar - show immediately, no loading state
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 56, height: 56)
                .overlay {
                    Text(project.name.prefix(1).uppercased())
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(project.name)
                        .font(.system(size: 17, weight: .medium))
                        .lineLimit(1)
                    
                    // Online status indicator
                    if nostrManager.isProjectOnline(project.id) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .padding(.leading, 4)
                    }
                    
                    Spacer()
                    
                    if let activity = lastActivity, activity != Date.distantPast {
                        Text(activity, style: .relative)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
                
                HStack {
                    if let description = project.description {
                        Text(description)
                            .font(.system(size: 15))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    } else if conversationCount == 0 {
                        Text("No conversations yet")
                            .font(.system(size: 15))
                            .foregroundColor(.gray)
                            .italic()
                    } else {
                        Text("\(conversationCount) conversation\(conversationCount == 1 ? "" : "s")")
                            .font(.system(size: 15))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    if availableAgents > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.green)
                            Text("\(availableAgents) agent\(availableAgents == 1 ? "" : "s")")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
}