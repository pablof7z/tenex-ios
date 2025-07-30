import SwiftUI
import NDKSwift

struct AgentListView: View {
    let agents: [NDKProjectStatus.AgentStatus]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(agents) { agent in
                    NavigationLink(destination: AgentProfileView(agent: agent)) {
                        AgentRowView(agent: agent)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if agent.id != agents.last?.id {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
            }
        }
        .background(Color(UIColor.systemBackground))
    }
}

struct AgentRowView: View {
    let agent: NDKProjectStatus.AgentStatus
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(getAgentColor(for: agent.slug))
                .frame(width: 52, height: 52)
                .overlay(
                    Text(agent.name.prefix(2).uppercased())
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(agent.name)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(agent.status == "available" ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    
                    Text(agent.status)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                    
                    if let lastSeen = agent.lastSeen {
                        Text("• \(lastSeen, style: .relative) ago")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    
    private func getAgentColor(for slug: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .red, .pink, .indigo, .teal]
        let index = abs(slug.hashValue) % colors.count
        return colors[index]
    }
}

// Voice selector is now only accessible from the agent profile
struct VoiceSelectorView: View {
    let agent: NDKProjectStatus.AgentStatus
    let audioManager: AudioManager
    @Binding var isPresented: Bool
    
    @State private var selectedVoiceId: String?
    @State private var isPlaying = false
    @State private var playingVoiceId: String?
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(AudioManager.voiceOptions, id: \.identifier) { voice in
                        HStack {
                            Text(voice.name)
                                .font(.body)
                            
                            Spacer()
                            
                            // Play button
                            Button(action: {
                                playVoiceSample(voiceId: voice.identifier)
                            }) {
                                Image(systemName: playingVoiceId == voice.identifier ? "speaker.wave.2.fill" : "play.circle")
                                    .foregroundColor(.blue)
                            }
                            .disabled(isPlaying)
                            
                            // Selection indicator
                            if selectedVoiceId == voice.identifier ||
                               (selectedVoiceId == nil && audioManager.getVoiceForAgent(slug: agent.slug) == voice.identifier) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedVoiceId = voice.identifier
                        }
                    }
                } header: {
                    Text("Available Voices")
                }
            }
            .navigationTitle("Select Voice for \(agent.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let voiceId = selectedVoiceId {
                            audioManager.setVoiceForAgent(slug: agent.slug, voiceIdentifier: voiceId)
                        }
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            selectedVoiceId = audioManager.getVoiceForAgent(slug: agent.slug)
        }
    }
    
    private func playVoiceSample(voiceId: String) {
        guard !isPlaying else { return }
        
        isPlaying = true
        playingVoiceId = voiceId
        
        Task {
            let sampleText = "Hello, I'm \(agent.name). This is how I sound with this voice."
            
            // Temporarily set the voice for this agent to preview
            let previousVoiceId = audioManager.getVoiceForAgent(slug: agent.slug)
            audioManager.setVoiceForAgent(slug: agent.slug, voiceIdentifier: voiceId)
            
            await audioManager.speakText(sampleText, agentPubkey: agent.id, agentSlug: agent.slug) {
                Task { @MainActor in
                    isPlaying = false
                    playingVoiceId = nil
                    
                    // Restore previous voice if not saved
                    if let previousId = previousVoiceId {
                        audioManager.setVoiceForAgent(slug: agent.slug, voiceIdentifier: previousId)
                    }
                }
            }
        }
    }
}