import SwiftUI
import NDKSwift
import AVFoundation
import CryptoKit

struct CallView: View {
    let conversation: NDKConversation
    let project: NDKProject
    
    @Environment(NostrManager.self) var nostrManager
    @Environment(\.dismiss) var dismiss
    @StateObject private var audioManager = AudioManager.shared
    
    @State private var agentResponses: [String: AgentResponse] = [:] // agentPubkey -> response
    @State private var currentSpeakingAgent: String? = nil
    @State private var streamingSubscription: Task<Void, Never>?
    @State private var lastSpokenContent: [String: String] = [:] // agentPubkey -> last spoken content
    @State private var isCallActive = true
    @State private var isShowingVoiceRecorder = false
    @State private var lastSpeakingAgent: String? = nil
    @State private var isRecording = false
    @State private var currentTranscript = ""
    @State private var audioURL: URL?
    @State private var recordingStartTime: Date?
    @State private var waveformAmplitudes: [Float] = []
    @State private var currentAmplitude: Float = 0.0
    
    struct AgentResponse {
        let agentPubkey: String
        var content: String
        let timestamp: Date
        var hasFinishedSpeaking: Bool = false
        var event: NDKEvent // Store the full event for replies
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color.black
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Simple header
                    HStack {
                        Button(action: endCall) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding()
                        
                        Spacer()
                    }
                    
                    // Main content area
                    if agentResponses.isEmpty {
                        // Waiting state
                        VStack(spacing: 20) {
                            Spacer()
                            
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                            
                            Text("Connecting to agents...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Spacer()
                        }
                    } else {
                        // Agent display
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 40) {
                                Spacer(minLength: 20)
                                
                                ForEach(Array(agentResponses.values).sorted(by: { $0.timestamp < $1.timestamp }), id: \.agentPubkey) { response in
                                    AgentAvatarView(
                                        agentPubkey: response.agentPubkey,
                                        isSpeaking: currentSpeakingAgent == response.agentPubkey,
                                        hasFinished: response.hasFinishedSpeaking,
                                        content: response.content,
                                        project: project
                                    )
                                }
                                
                                Spacer(minLength: 100)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 40)
                        }
                    }
                    
                    // Bottom controls
                    VStack(spacing: 16) {
                        // Show transcript while recording
                        if isRecording && !currentTranscript.isEmpty {
                            Text(currentTranscript)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(20)
                                .transition(.opacity)
                        }
                        
                        // Connection status
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isCallActive ? Color.green : Color.gray)
                                .frame(width: 6, height: 6)
                            
                            Text(isCallActive ? "Connected" : "Disconnected")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        // Call controls
                        HStack(spacing: 24) {
                            // Microphone button
                            VoiceReactiveMicButton(
                                isRecording: isRecording,
                                currentAmplitude: currentAmplitude,
                                action: toggleRecording
                            )
                            
                            // End call button
                            Button(action: endCall) {
                                ZStack {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 72, height: 72)
                                    
                                    Image(systemName: "phone.down.fill")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .shadow(color: Color.red.opacity(0.4), radius: 10, x: 0, y: 5)
                        }
                    }
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 30)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            streamingSubscription = Task {
                await subscribeToAgentResponses()
            }
        }
        .onDisappear {
            streamingSubscription?.cancel()
            audioManager.stopTTS()
            if isRecording {
                audioManager.stopRecording()
            }
        }
    }
    
    private func subscribeToAgentResponses() async {
        // Subscribe to kind 21111 events that tag this conversation
        let filter = NDKFilter(
            kinds: [21111], // Agent streaming responses
            tags: ["e": [conversation.id]]
        )
        
        let responseSource = nostrManager.ndk.subscribe(
            filter: filter,
            cachePolicy: .networkOnly // Don't cache streaming responses
        )
        
        for await event in responseSource.events {
            await handleAgentResponse(event)
        }
    }
    
    private func handleAgentResponse(_ event: NDKEvent) async {
        let agentPubkey = event.pubkey
        let newContent = event.content
        
        // Update or create agent response
        if var existingResponse = agentResponses[agentPubkey] {
            existingResponse.content = newContent
            existingResponse.event = event
            agentResponses[agentPubkey] = existingResponse
        } else {
            agentResponses[agentPubkey] = AgentResponse(
                agentPubkey: agentPubkey,
                content: newContent,
                timestamp: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
                event: event
            )
        }
        
        // Extract only the new portion of content to speak
        let lastSpoken = lastSpokenContent[agentPubkey] ?? ""
        if newContent.hasPrefix(lastSpoken) && newContent.count > lastSpoken.count {
            let newPortion = String(newContent.dropFirst(lastSpoken.count))
            
            // Update last spoken content
            lastSpokenContent[agentPubkey] = newContent
            
            // Speak the new portion
            await speakContent(newPortion, for: agentPubkey)
        }
    }
    
    private func speakContent(_ content: String, for agentPubkey: String) async {
        // Set current speaking agent
        await MainActor.run {
            currentSpeakingAgent = agentPubkey
            lastSpeakingAgent = agentPubkey
        }
        
        // Use TTS to speak the content
        await audioManager.speak(content)
        
        // After speaking is done, update UI
        await MainActor.run {
            if currentSpeakingAgent == agentPubkey {
                currentSpeakingAgent = nil
            }
            
            // Mark agent as finished speaking if this was their final content
            if var response = agentResponses[agentPubkey] {
                response.hasFinishedSpeaking = true
                agentResponses[agentPubkey] = response
            }
        }
    }
    
    private func endCall() {
        isCallActive = false
        audioManager.stopTTS()
        dismiss()
    }
    
    private func getLastVisibleMessage() -> NDKEvent {
        // Get the last agent response event, or fall back to the conversation event
        if let lastAgent = lastSpeakingAgent,
           let lastResponse = agentResponses[lastAgent] {
            return lastResponse.event
        }
        return conversation.event
    }
    
    private func getSelectedAgents() -> Set<String> {
        var agents = Set<String>()
        if let lastAgent = lastSpeakingAgent {
            agents.insert(lastAgent)
        }
        return agents
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        Task {
            // Request permissions if needed
            await audioManager.requestPermissions()
            
            guard audioManager.microphonePermissionGranted && audioManager.speechPermissionGranted else {
                return
            }
            
            recordingStartTime = Date()
            currentTranscript = ""
            waveformAmplitudes = []
            
            await audioManager.startRecordingWithFile { transcript, url, amplitude in
                if !transcript.isEmpty {
                    currentTranscript = transcript
                }
                if let url = url {
                    audioURL = url
                }
                if let amplitude = amplitude {
                    waveformAmplitudes.append(amplitude)
                    // Update current amplitude for visual feedback
                    currentAmplitude = amplitude
                }
            }
            
            isRecording = true
        }
    }
    
    private func stopRecording() {
        audioManager.stopRecording()
        isRecording = false
        
        // Process and publish the recording
        if let audioURL = audioURL,
           !currentTranscript.isEmpty,
           let recordingStartTime = recordingStartTime {
            
            let duration = Date().timeIntervalSince(recordingStartTime)
            
            Task {
                await publishAudioReply(
                    audioURL: audioURL,
                    transcript: currentTranscript,
                    duration: duration,
                    waveformAmplitudes: waveformAmplitudes
                )
            }
        }
        
        // Reset recording state
        audioURL = nil
        currentTranscript = ""
        recordingStartTime = nil
        waveformAmplitudes = []
        currentAmplitude = 0.0
    }
    
    private func publishAudioReply(
        audioURL: URL,
        transcript: String,
        duration: TimeInterval,
        waveformAmplitudes: [Float]
    ) async {
        do {
            // Create reply with transcript as content
            _ = try await nostrManager.replyToConversation(
                conversation,
                content: transcript,
                mentionedAgentPubkeys: Array(getSelectedAgents()),
                lastVisibleMessage: getLastVisibleMessage()
            )
            
            // Read audio data
            let audioData = try Data(contentsOf: audioURL)
            
            // Upload to Blossom
            let blossomClient = BlossomClient()
            let uploadResult = try await blossomClient.uploadWithAuth(
                data: audioData,
                mimeType: "audio/m4a",
                to: "https://blossom.primal.net",
                signer: nostrManager.ndk.signer!,
                ndk: nostrManager.ndk
            )
            
            // Create waveform string
            let waveformString = waveformAmplitudes
                .map { String(format: "%.2f", $0) }
                .joined(separator: " ")
            
            // Create audio event per NIP-94
            var builder = NDKEventBuilder(ndk: nostrManager.ndk)
                .content(transcript)
                .kind(1063)
                .tag(["url", uploadResult.url])
                .tag(["m", "audio/m4a"])
                .tag(["x", calculateSHA256(of: audioData)])
                .tag(["size", String(audioData.count)])
                .tag(["e", conversation.id])
                .tag(["a", project.addressableId])
            
            if !waveformString.isEmpty {
                builder = builder
                    .tag(["waveform", waveformString])
                    .tag(["duration", String(Int(duration))])
            }
            
            // Add agent mentions
            for agentPubkey in getSelectedAgents() {
                builder = builder.tag(["p", agentPubkey])
            }
            
            let audioEvent = try await builder.build()
            _ = try await nostrManager.ndk.publish(audioEvent)
            
        } catch {
            print("Failed to publish audio reply: \(error)")
        }
    }
    
    private func calculateSHA256(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

struct AgentAvatarView: View {
    let agentPubkey: String
    let isSpeaking: Bool
    let hasFinished: Bool
    let content: String
    let project: NDKProject
    
    @Environment(NostrManager.self) var nostrManager
    @State private var agentInfo: NDKProjectStatus.AgentStatus?
    @State private var animationScale: CGFloat = 1.0
    
    private var displaySize: CGFloat {
        if isSpeaking {
            return 100
        } else {
            return 80
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Subtle glow effect when speaking
                if isSpeaking {
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.blue.opacity(0.3),
                                    Color.blue.opacity(0.1),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: displaySize * 0.3,
                                endRadius: displaySize * 0.8
                            )
                        )
                        .frame(width: displaySize * 1.5, height: displaySize * 1.5)
                        .blur(radius: 10)
                }
                
                // Avatar circle
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(white: 0.2),
                                Color(white: 0.15)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: displaySize, height: displaySize)
                    .overlay(
                        Circle()
                            .stroke(
                                isSpeaking ? Color.blue : Color.white.opacity(0.2),
                                lineWidth: isSpeaking ? 2 : 1
                            )
                    )
                    .overlay(avatarContent)
                    .scaleEffect(isSpeaking ? animationScale : 1.0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: displaySize)
            }
            
            // Agent name
            if let agentInfo = agentInfo {
                Text(agentInfo.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(isSpeaking ? 1.0 : 0.8)
            }
            
            // Speaking indicator or content preview
            if isSpeaking {
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 4, height: 4)
                            .scaleEffect(isSpeaking ? 1.0 : 0.5)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.1),
                                value: isSpeaking
                            )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            if isSpeaking {
                withAnimation(
                    Animation.easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true)
                ) {
                    animationScale = 1.05
                }
            }
        }
        .task {
            // Find agent info from available agents
            let agents = nostrManager.getAvailableAgents(for: project.addressableId)
            agentInfo = agents.first { $0.id == agentPubkey }
        }
    }
    
    @ViewBuilder
    private var avatarContent: some View {
        if let agentInfo = agentInfo {
            Text(String(agentInfo.name.prefix(2)).uppercased())
                .font(.system(size: displaySize * 0.35, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        } else {
            Text(String(agentPubkey.prefix(4)).uppercased())
                .font(.system(size: displaySize * 0.3, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

struct VoiceReactiveMicButton: View {
    let isRecording: Bool
    let currentAmplitude: Float
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Voice-reactive glow when recording
                if isRecording {
                    VoiceGlow(amplitude: currentAmplitude)
                }
                
                Circle()
                    .fill(isRecording ? Color.red : Color.white.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .scaleEffect(isRecording ? 1.0 + CGFloat(currentAmplitude) * 0.1 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: currentAmplitude)
                
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .scaleEffect(isRecording ? 1.0 + CGFloat(currentAmplitude) * 0.05 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: currentAmplitude)
            }
        }
        .shadow(color: isRecording ? Color.red.opacity(0.4) : Color.white.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

struct VoiceGlow: View {
    let amplitude: Float
    
    private var glowSize: CGFloat {
        80 + (CGFloat(amplitude) * 60)
    }
    
    private var glowRadius: CGFloat {
        40 + (CGFloat(amplitude) * 40)
    }
    
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.red.opacity(0.6),
                        Color.red.opacity(0.3),
                        Color.red.opacity(0.1)
                    ]),
                    center: .center,
                    startRadius: 30,
                    endRadius: glowRadius
                )
            )
            .frame(width: glowSize, height: glowSize)
            .blur(radius: 5)
            .animation(.easeOut(duration: 0.1), value: amplitude)
    }
}