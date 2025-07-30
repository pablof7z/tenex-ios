import SwiftUI
import NDKSwift

struct ProjectListView: View {
    @Environment(NostrManager.self) var nostrManager
    @State private var searchText = ""
    @State private var conversationCounts: [String: Int] = [:] // projectId -> count
    @State private var lastActivityDates: [String: Date] = [:] // projectId -> date
    @State private var lessonCounts: [String: Int] = [:] // projectId -> lesson count
    @State private var projectLessons: [String: [NDKLesson]] = [:] // projectId -> lessons
    @State private var projectConversations: [String: [NDKConversation]] = [:] // projectId -> conversations
    
    var filteredAndSortedProjects: [NDKProject] {
        // Get projects from NostrManager (single source of truth)
        let projects = nostrManager.projects
        
        // Filter by search
        let filtered = searchText.isEmpty ? projects : projects.filter { project in
            project.name.localizedCaseInsensitiveContains(searchText)
        }
        
        // Sort by online status first, then by most recent activity
        return filtered.sorted { project1, project2 in
            let isOnline1 = nostrManager.isProjectOnline(project1.id)
            let isOnline2 = nostrManager.isProjectOnline(project2.id)
            
            // If one is online and the other isn't, online comes first
            if isOnline1 != isOnline2 {
                return isOnline1
            }
            
            // Otherwise sort by activity date
            let date1 = lastActivityDates[project1.addressableId] ?? Date.distantPast
            let date2 = lastActivityDates[project2.addressableId] ?? Date.distantPast
            return date1 > date2
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredAndSortedProjects.isEmpty && nostrManager.hasActiveUser {
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
                                    lessonCount: lessonCounts[project.addressableId] ?? 0,
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
                // Stream conversations and lessons for existing projects
                for project in nostrManager.projects {
                    Task {
                        await streamConversations(for: project)
                    }
                    Task {
                        await streamLessons(for: project)
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
        
        var conversations: [NDKConversation] = []
        
        for await event in conversationSource.events {
            let conversation = NDKConversation(event: event)
            
            if !conversations.contains(where: { $0.id == conversation.id }) {
                conversations.append(conversation)
                
                await MainActor.run {
                    // Update conversation count - create new dictionary to trigger UI update
                    var updatedCounts = conversationCounts
                    updatedCounts[project.addressableId] = conversations.count
                    conversationCounts = updatedCounts
                    
                    // Store conversations for the project
                    var updatedConversations = projectConversations
                    updatedConversations[project.addressableId] = conversations
                    projectConversations = updatedConversations
                    
                    // Update last activity date - create new dictionary to trigger UI update
                    updateLastActivityDate(for: project.addressableId)
                }
            }
        }
    }
    
    private func streamLessons(for project: NDKProject) async {
        let lessonFilter = NDKFilter(
            kinds: [NDKLesson.kind],
            tags: ["a": [project.addressableId]]
        )
        
        let lessonSource = nostrManager.ndk.observe(
            filter: lessonFilter,
            maxAge: 300,
            cachePolicy: .cacheWithNetwork
        )
        
        var lessons: [NDKLesson] = []
        
        for await event in lessonSource.events {
            let lesson = NDKLesson(event: event)
            
            if !lessons.contains(where: { $0.id == lesson.id }) {
                lessons.append(lesson)
                
                await MainActor.run {
                    // Update lesson count
                    var updatedCounts = lessonCounts
                    updatedCounts[project.addressableId] = lessons.count
                    lessonCounts = updatedCounts
                    
                    // Store lessons for the project
                    var updatedLessons = projectLessons
                    updatedLessons[project.addressableId] = lessons
                    projectLessons = updatedLessons
                    
                    // Update last activity date considering both conversations and lessons
                    updateLastActivityDate(for: project.addressableId)
                }
            }
        }
    }
    
    private func updateLastActivityDate(for projectId: String) {
        // Get the most recent activity from either conversations or lessons
        let conversationDate = projectConversations[projectId]?
            .map { $0.createdAt }
            .max() ?? Date.distantPast
        
        let lessonDate = projectLessons[projectId]?
            .map { $0.createdAt }
            .max() ?? Date.distantPast
        
        let mostRecentDate = max(conversationDate, lessonDate)
        
        if mostRecentDate != Date.distantPast {
            var updatedDates = lastActivityDates
            updatedDates[projectId] = mostRecentDate
            lastActivityDates = updatedDates
        }
    }
}

struct ProjectRowView: View {
    let project: NDKProject
    let conversationCount: Int
    let lessonCount: Int
    let lastActivity: Date?
    @Environment(NostrManager.self) var nostrManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar with online indicator
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Text(project.name.prefix(1).uppercased())
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                
                // Online status indicator aligned with avatar
                if nostrManager.isProjectOnline(project.id) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 14, height: 14)
                        .overlay {
                            Circle()
                                .stroke(Color(UIColor.systemBackground), lineWidth: 2)
                        }
                        .offset(x: 2, y: 2)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(project.name)
                        .font(.system(size: 17, weight: .medium))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let activity = lastActivity, activity != Date.distantPast {
                        Text(activity, style: .relative)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
                
                if let description = project.description {
                    Text(description)
                        .font(.system(size: 15))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                } else if conversationCount == 0 && lessonCount == 0 {
                    Text("No activity yet")
                        .font(.system(size: 15))
                        .foregroundColor(.gray)
                        .italic()
                } else {
                    HStack(spacing: 12) {
                        if conversationCount > 0 {
                            Text("\(conversationCount) conversation\(conversationCount == 1 ? "" : "s")")
                                .font(.system(size: 15))
                                .foregroundColor(.gray)
                        }
                        if lessonCount > 0 {
                            Text("\(lessonCount) lesson\(lessonCount == 1 ? "" : "s")")
                                .font(.system(size: 15))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
}