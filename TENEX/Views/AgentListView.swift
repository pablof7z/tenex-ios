import SwiftUI
import AVFoundation

// Helper class for voice sample playback with completion
@MainActor
class VoiceSampleSynthesizer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?
    
    init(completion: @escaping () -> Void) {
        self.completion = completion
        super.init()
        synthesizer.delegate = self
    }
    
    func speak(_ utterance: AVSpeechUtterance) {
        synthesizer.speak(utterance)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completion?()
    }
}

struct AgentListView: View {
    let agents: [NDKAgent]
    @StateObject private var audioManager = AudioManager()
    @State private var selectedAgent: NDKAgent?
    @State private var showVoiceSelector = false
    
    var body: some View {
        List {
            ForEach(agents) { agent in
                AgentRowView(
                    agent: agent,
                    audioManager: audioManager,
                    onVoiceSelect: {
                        selectedAgent = agent
                        showVoiceSelector = true
                    }
                )
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showVoiceSelector) {
            if let agent = selectedAgent {
                VoiceSelectorView(
                    agent: agent,
                    audioManager: audioManager,
                    isPresented: $showVoiceSelector
                )
            }
        }
    }
}

struct AgentRowView: View {
    let agent: NDKAgent
    let audioManager: AudioManager
    let onVoiceSelect: () -> Void
    
    @State private var isPlaying = false
    
    var currentVoice: String {
        if let voiceId = audioManager.getVoiceForAgent(slug: agent.slug) {
            return AudioManager.voiceOptions.first { $0.identifier == voiceId }?.name ?? "Default"
        }
        return "Auto-assigned"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Agent info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name)
                        .font(.headline)
                    
                    if let role = agent.role {
                        Text(role)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Play sample button
                Button(action: playVoiceSample) {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.circle")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .disabled(isPlaying)
            }
            
            // Voice selection
            HStack {
                Text("Voice:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(action: onVoiceSelect) {
                    HStack {
                        Text(currentVoice)
                            .font(.subheadline)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func playVoiceSample() {
        isPlaying = true
        Task {
            let sampleText = "Hello, I'm \(agent.name). \(agent.description ?? "I'm here to help you with your tasks.")"
            await audioManager.speakText(sampleText, agentPubkey: agent.pubkey, agentSlug: agent.slug) {
                Task { @MainActor in
                    isPlaying = false
                }
            }
        }
    }
}

struct VoiceSelectorView: View {
    let agent: NDKAgent
    let audioManager: AudioManager
    @Binding var isPresented: Bool
    
    @State private var selectedVoiceId: String?
    @State private var isPlaying = false
    @State private var playingVoiceId: String?
    @State private var voiceSynthesizer: VoiceSampleSynthesizer?
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(AudioManager.voiceOptions, id: \.identifier) { voice in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(voice.name)
                                    .font(.body)
                            }
                            
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
            
            // Create a temporary utterance with the selected voice
            let utterance = AVSpeechUtterance(string: sampleText)
            utterance.rate = 0.52
            utterance.pitchMultiplier = 1.0
            utterance.volume = 0.9
            
            if let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
                utterance.voice = voice
            }
            
            // Create a voice sample synthesizer with completion
            voiceSynthesizer = VoiceSampleSynthesizer {
                Task { @MainActor in
                    isPlaying = false
                    playingVoiceId = nil
                }
            }
            
            voiceSynthesizer?.speak(utterance)
        }
    }
}