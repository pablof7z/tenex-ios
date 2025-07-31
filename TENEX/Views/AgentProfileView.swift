import SwiftUI
import NDKSwift

struct AgentProfileView: View {
    let agent: NDKProjectStatus.AgentStatus
    @Environment(NostrManager.self) var nostrManager
    @StateObject private var audioManager = AudioManager()
    @State private var selectedTab = 0
    @State private var showVoiceSelector = false
    @State private var isPlayingVoice = false
    @State private var lessons: [NDKLesson] = []
    @State private var lessonStreamTask: Task<Void, Never>?
    
    var currentVoice: String {
        if let voiceId = audioManager.getVoiceForAgent(slug: agent.slug) {
            return AudioManager.voiceOptions.first { $0.identifier == voiceId }?.name ?? "Default"
        }
        return "Auto-assigned"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Agent Header
            VStack(spacing: 12) {
                // Profile image placeholder
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Text(agent.name.prefix(1).uppercased())
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    )
                
                Text(agent.name)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(agent.status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let lastSeen = agent.lastSeen {
                    Text("Last seen \(lastSeen, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical)
            
            // Tab selector
            HStack(spacing: 0) {
                TabButton(
                    title: "Lessons",
                    count: lessons.count,
                    isSelected: selectedTab == 0,
                    action: { selectedTab = 0 }
                )
                
                TabButton(
                    title: "About",
                    count: 0,
                    isSelected: selectedTab == 1,
                    action: { selectedTab = 1 }
                )
                
                TabButton(
                    title: "Voice",
                    count: 0,
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
                // Lessons tab
                LessonsTabView(lessons: lessons, agent: agent)
            } else if selectedTab == 1 {
                // About tab
                AboutTabView(agent: agent)
            } else {
                // Voice tab
                VoiceTabView(
                    agent: agent,
                    audioManager: audioManager,
                    currentVoice: currentVoice,
                    isPlayingVoice: $isPlayingVoice,
                    showVoiceSelector: $showVoiceSelector,
                    playVoiceSample: playVoiceSample
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showVoiceSelector) {
            VoiceSelectorView(
                agent: agent,
                audioManager: audioManager,
                isPresented: $showVoiceSelector
            )
        }
        .task {
            await subscribeToLessons()
        }
        .onDisappear {
            lessonStreamTask?.cancel()
        }
    }
    
    private func playVoiceSample() {
        isPlayingVoice = true
        Task {
            let sampleText = "Hello, I'm \(agent.name). I'm here to help you with your tasks."
            await audioManager.speakText(sampleText, agentPubkey: agent.id, agentSlug: agent.slug) {
                Task { @MainActor in
                    isPlayingVoice = false
                }
            }
        }
    }
    
    private func subscribeToLessons() async {
        lessonStreamTask?.cancel()
        
        lessonStreamTask = Task {
            // Subscribe to lessons from this agent
            let subscription = await nostrManager.streamAgentLessons(agentPubkey: agent.id)
            
            for await event in subscription {
                if Task.isCancelled { break }

                print("lesson event")
                
                await MainActor.run {
                    let lesson = NDKLesson(event: event)
                    if !lessons.contains(where: { $0.id == lesson.id }) {
                        lessons.append(lesson)
                        lessons.sort { $0.createdAt > $1.createdAt }
                    }
                }
            }
        }
    }
}

// MARK: - Tab Views

struct LessonsTabView: View {
    let lessons: [NDKLesson]
    let agent: NDKProjectStatus.AgentStatus
    
    var body: some View {
        if lessons.isEmpty {
            ContentUnavailableView(
                "No Lessons Yet",
                systemImage: "book.closed",
                description: Text("\(agent.name) hasn't shared any lessons yet.")
            )
        } else {
            List {
                ForEach(lessons) { lesson in
                    NavigationLink(destination: LessonDetailView(lesson: lesson, agent: agent)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(lesson.title)
                                .font(.headline)
                            
                            Text(lesson.content)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                            
                            HStack {
                                if let lessonType = lesson.lessonType {
                                    Label(lessonType, systemImage: "tag")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                
                                Spacer()
                                
                                Text(lesson.createdAt, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

struct AboutTabView: View {
    let agent: NDKProjectStatus.AgentStatus
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    DetailRow(label: "Slug", value: agent.slug)
                    DetailRow(label: "Agent ID", value: String(agent.id.prefix(16)) + "...")
                    DetailRow(label: "Status", value: agent.status)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                
                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
    }
}

struct VoiceTabView: View {
    let agent: NDKProjectStatus.AgentStatus
    let audioManager: AudioManager
    let currentVoice: String
    @Binding var isPlayingVoice: Bool
    @Binding var showVoiceSelector: Bool
    let playVoiceSample: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Current voice settings
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Voice")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(currentVoice)
                                .font(.body)
                        }
                        
                        Spacer()
                        
                        Button(action: { showVoiceSelector = true }) {
                            Text("Change")
                                .font(.body)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    // Play Voice Sample
                    Button(action: playVoiceSample) {
                        HStack {
                            Image(systemName: isPlayingVoice ? "speaker.wave.2.fill" : "play.circle.fill")
                            Text(isPlayingVoice ? "Playing..." : "Play Voice Sample")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isPlayingVoice)
                }
                .padding(.horizontal)
                
                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}