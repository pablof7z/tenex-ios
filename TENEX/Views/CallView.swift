import SwiftUI
import NDKSwift
import AVFoundation

struct CallView: View {
    let conversationId: String
    let project: NDKProject
    
    @Environment(NostrManager.self) var nostrManager
    @Environment(\.dismiss) var dismiss
    @StateObject private var audioManager = AudioManager.shared
    
    @State private var agentResponses: [String: AgentResponse] = [:] // agentPubkey -> response
    @State private var currentSpeakingAgent: String? = nil
    @State private var streamingSubscription: Task<Void, Never>?
    @State private var lastSpokenContent: [String: String] = [:] // agentPubkey -> last spoken content
    @State private var isCallActive = true
    
    struct AgentResponse {
        let agentPubkey: String
        var content: String
        let timestamp: Date
        var hasFinishedSpeaking: Bool = false
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
                        // Connection status
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isCallActive ? Color.green : Color.gray)
                                .frame(width: 6, height: 6)
                            
                            Text(isCallActive ? "Connected" : "Disconnected")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
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
        }
    }
    
    private func subscribeToAgentResponses() async {
        // Subscribe to kind 21111 events that tag this conversation
        let filter = NDKFilter(
            kinds: [21111], // Agent streaming responses
            tags: ["e": [conversationId]]
        )
        
        let responseSource = nostrManager.ndk.observe(
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
            agentResponses[agentPubkey] = existingResponse
        } else {
            agentResponses[agentPubkey] = AgentResponse(
                agentPubkey: agentPubkey,
                content: newContent,
                timestamp: Date(timeIntervalSince1970: TimeInterval(event.createdAt))
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