import SwiftUI
import AVFoundation
import Speech
import NDKSwift
import Foundation
import CryptoKit

struct VoiceOnlyConversationView: View {
    let project: NDKProject
    let onConversationCreated: ((NDKConversation) -> Void)?
    let replyToConversation: NDKConversation?
    let lastVisibleMessage: NDKEvent?
    
    @Environment(NostrManager.self) var nostrManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    init(project: NDKProject, 
         replyToConversation: NDKConversation? = nil,
         lastVisibleMessage: NDKEvent? = nil,
         onConversationCreated: ((NDKConversation) -> Void)? = nil) {
        self.project = project
        self.replyToConversation = replyToConversation
        self.lastVisibleMessage = lastVisibleMessage
        self.onConversationCreated = onConversationCreated
    }
    
    @StateObject private var audioManager = AudioManager.shared
    @State private var isRecording = false
    @State private var transcribedText = ""
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isProcessing = false
    @State private var waveformAmplitudes: [Float] = []
    @State private var selectedAgents: Set<String> = [] // agent pubkeys
    @State private var recordedAudioURL: URL?
    @State private var isPaused = false
    @State private var hasStartedRecording = false
    @State private var isEditingTranscription = false
    @State private var editedText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    // No recording duration limit
    
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var availableAgents: [NDKProjectStatus.AgentStatus] {
        nostrManager.getAvailableAgents(for: project.addressableId)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Clean background
                Color(colorScheme == .dark ? UIColor.systemBackground : UIColor.secondarySystemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer()
                        .frame(height: 40)
                    
                    // Recording duration
                    Text(formattedDuration)
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                    
                    // Waveform visualization
                    WaveformView(amplitudes: waveformAmplitudes, isRecording: isRecording)
                        .frame(height: 60)
                        .padding(.horizontal, 32)
                    
                    // Transcribed text display with edit capability
                    if isEditingTranscription {
                        // Edit mode
                        VStack(spacing: 16) {
                            ScrollView {
                                TextField("Edit transcription...", text: $editedText, axis: .vertical)
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                    .focused($isTextFieldFocused)
                                    .lineLimit(nil)
                            }
                            .frame(maxHeight: 200)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(UIColor.systemGray6))
                                    .padding(.horizontal, 24)
                            )
                            
                            // Edit mode buttons
                            HStack(spacing: 20) {
                                Button(action: cancelEdit) {
                                    Text("Cancel")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.red)
                                }
                                
                                Button(action: saveEdit) {
                                    Text("Save")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding(.vertical, 20)
                    } else {
                        // View mode - tap to edit
                        ScrollView {
                            Text(transcribedText.isEmpty ? "Listening..." : transcribedText)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .animation(.easeInOut, value: transcribedText)
                                .onTapGesture {
                                    if !transcribedText.isEmpty && !isRecording {
                                        startEditing()
                                    }
                                }
                        }
                        .frame(maxHeight: 200)
                        .padding(.vertical, 20)
                        .overlay(alignment: .topTrailing) {
                            // Edit hint when text is available
                            if !transcribedText.isEmpty && !isRecording {
                                Text("Tap to edit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 32)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Spacer()
                    
                    // Recording controls
                    VStack(spacing: 32) {
                        // Main recording indicator
                        ZStack {
                            // Pulse animation when recording
                            if isRecording && !isPaused {
                                Circle()
                                    .fill(Color.red.opacity(0.2))
                                    .frame(width: 120, height: 120)
                                    .scaleEffect(isRecording ? 1.3 : 1.0)
                                    .opacity(isRecording ? 0 : 0.3)
                                    .animation(
                                        Animation.easeOut(duration: 1.5)
                                            .repeatForever(autoreverses: false),
                                        value: isRecording
                                    )
                            }
                            
                            // Stop button
                            Button(action: handleRecordingToggle) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 80, height: 80)
                                    .overlay {
                                        if isProcessing {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(1.5)
                                        } else {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.white)
                                                .frame(width: 24, height: 24)
                                        }
                                    }
                            }
                            .disabled(isProcessing || !hasStartedRecording)
                        }
                        
                        // Bottom controls
                        HStack(spacing: 60) {
                            // Pause button
                            if hasStartedRecording && !isProcessing {
                                Button(action: handlePauseResume) {
                                    Circle()
                                        .fill(Color(UIColor.systemGray5))
                                        .frame(width: 56, height: 56)
                                        .overlay {
                                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(.primary)
                                        }
                                }
                            } else {
                                Spacer()
                                    .frame(width: 56)
                            }
                            
                            // Send button
                            if !transcribedText.isEmpty && recordedAudioURL != nil && !isEditingTranscription {
                                Button(action: createVoiceConversation) {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 56, height: 56)
                                        .overlay {
                                            Image(systemName: "arrow.up")
                                                .font(.system(size: 22, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                }
                                .disabled(isProcessing)
                            } else {
                                Spacer()
                                    .frame(width: 56)
                            }
                        }
                    }
                    
                    // Agent selection (when not recording and not editing)
                    if !isRecording && !availableAgents.isEmpty && !isEditingTranscription {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Mention Agents")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 32)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(availableAgents, id: \.id) { agent in
                                        AgentPillView(
                                            agent: agent,
                                            isSelected: selectedAgents.contains(agent.id)
                                        ) {
                                            toggleAgentSelection(agent.id)
                                        }
                                    }
                                }
                                .padding(.horizontal, 32)
                            }
                        }
                    }
                    
                    Spacer()
                        .frame(height: 60)
                }
            }
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .onAppear {
            requestPermissions()
            // Automatically start recording after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                startRecording()
            }
        }
        .onDisappear {
            // Clean up recording and timer
            timer?.invalidate()
            timer = nil
            if isRecording {
                stopRecording()
            }
        }
    }
    
    private func requestPermissions() {
        Task {
            await audioManager.requestPermissions()
        }
    }
    
    private func handleRecordingToggle() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        Task {
            transcribedText = ""
            waveformAmplitudes = []
            recordingDuration = 0
            
            // Start recording with transcription
            await audioManager.startRecordingWithFile { transcription, audioURL, amplitude in
                // Only update transcribedText if the transcription is not empty
                // This prevents amplitude updates from clearing the transcription
                if !transcription.isEmpty {
                    self.transcribedText = transcription
                }
                self.recordedAudioURL = audioURL
                
                // Update waveform
                if let amp = amplitude {
                    self.waveformAmplitudes.append(amp)
                    // Keep only recent amplitudes for visualization
                    if self.waveformAmplitudes.count > 100 {
                        self.waveformAmplitudes.removeFirst()
                    }
                }
            }
            
            isRecording = true
            hasStartedRecording = true
            isPaused = false
            
            // Start timer
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if !self.isPaused {
                    recordingDuration += 0.1
                }
            }
        }
    }
    
    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        audioManager.stopRecording()
        isRecording = false
    }
    
    private func getButtonColor() -> Color {
        if isProcessing {
            return Color.gray
        } else if isRecording {
            return Color.red
        } else {
            return Color.primary
        }
    }
    
    private func handlePauseResume() {
        if isPaused {
            // Resume recording
            audioManager.resumeRecording()
            isPaused = false
        } else {
            // Pause recording
            audioManager.pauseRecording()
            isPaused = true
        }
    }
    
    private func toggleAgentSelection(_ agentId: String) {
        if selectedAgents.contains(agentId) {
            selectedAgents.remove(agentId)
        } else {
            selectedAgents.insert(agentId)
        }
    }
    
    private func startEditing() {
        editedText = transcribedText
        isEditingTranscription = true
        isTextFieldFocused = true
    }
    
    private func cancelEdit() {
        isEditingTranscription = false
        editedText = ""
        isTextFieldFocused = false
    }
    
    private func saveEdit() {
        transcribedText = editedText
        isEditingTranscription = false
        isTextFieldFocused = false
    }
    
    private func createVoiceConversation() {
        guard let audioURL = recordedAudioURL,
              !transcribedText.isEmpty else { return }
        
        isProcessing = true
        
        Task {
            do {
                if let existingConversation = replyToConversation {
                    // Create a voice reply to the existing conversation
                    let replyEvent = try await nostrManager.replyToConversation(
                        existingConversation,
                        content: transcribedText,
                        mentionedAgentPubkeys: Array(selectedAgents),
                        lastVisibleMessage: lastVisibleMessage
                    )
                    
                    // Upload audio and create audio reply event
                    try await uploadAudioAndCreateReplyEvent(
                        audioURL: audioURL,
                        replyToEvent: replyEvent,
                        conversation: existingConversation,
                        transcription: transcribedText,
                        duration: recordingDuration
                    )
                } else {
                    // Create new conversation
                    let conversation = try await nostrManager.createConversation(
                        in: project,
                        title: nil,
                        content: transcribedText,
                        mentionedAgentPubkeys: Array(selectedAgents)
                    )
                    
                    // Upload audio to blossom server and create audio event
                    try await uploadAudioAndCreateEvent(
                        audioURL: audioURL,
                        conversation: conversation,
                        transcription: transcribedText,
                        duration: recordingDuration
                    )
                    
                    onConversationCreated?(conversation)
                }
                
                dismiss()
            } catch {
                print("Failed to create voice conversation: \(error)")
                isProcessing = false
            }
        }
    }
    
    private func uploadAudioAndCreateEvent(
        audioURL: URL,
        conversation: NDKConversation,
        transcription: String,
        duration: TimeInterval
    ) async throws {
        // Read audio data from file
        let audioData = try Data(contentsOf: audioURL)
        
        // Upload audio file to blossom server using BlossomClient
        let blossomClient = BlossomClient()
        let uploadResult = try await blossomClient.uploadWithAuth(
            data: audioData,
            mimeType: "audio/m4a",
            to: "https://blossom.primal.net", // Default server, you might want to make this configurable
            signer: nostrManager.ndk.signer!,
            ndk: nostrManager.ndk
        )
        
        let blossomURL = URL(string: uploadResult.url)!
        
        // Create waveform data for imeta tag
        let waveformString = waveformAmplitudes
            .map { String(format: "%.2f", $0) }
            .joined(separator: " ")
        
        // Create audio event per NIP-94 (kind 1063 for file metadata)
        var builder = NDKEventBuilder(ndk: nostrManager.ndk)
            .content(transcription) // NIP-94 uses content for description
            .kind(1063) // NIP-94 file metadata event
            .tag(["url", blossomURL.absoluteString])
            .tag(["m", "audio/m4a"]) // MIME type
            .tag(["x", calculateSHA256(of: audioData)]) // File hash
            .tag(["size", String(audioData.count)]) // File size in bytes
            .tag(["e", conversation.id]) // Reference the conversation
            .tag(["a", project.addressableId]) // Reference the project
        
        // Add optional tags
        if !waveformString.isEmpty {
            builder = builder
                .tag(["waveform", waveformString])
                .tag(["duration", String(Int(duration))])
        }
        
        // Add agent mentions using p tags
        for agentPubkey in selectedAgents {
            builder = builder.tag(["p", agentPubkey])
        }
        
        let audioEvent = try await builder.build()
        try await nostrManager.ndk.publish(audioEvent)
    }
    
    private func uploadAudioAndCreateReplyEvent(
        audioURL: URL,
        replyToEvent: NDKEvent,
        conversation: NDKConversation,
        transcription: String,
        duration: TimeInterval
    ) async throws {
        // Read audio data from file
        let audioData = try Data(contentsOf: audioURL)
        
        // Upload audio file to blossom server using BlossomClient
        let blossomClient = BlossomClient()
        let uploadResult = try await blossomClient.uploadWithAuth(
            data: audioData,
            mimeType: "audio/m4a",
            to: "https://blossom.primal.net",
            signer: nostrManager.ndk.signer!,
            ndk: nostrManager.ndk
        )
        
        let blossomURL = URL(string: uploadResult.url)!
        
        // Create waveform data for imeta tag
        let waveformString = waveformAmplitudes
            .map { String(format: "%.2f", $0) }
            .joined(separator: " ")
        
        // Create audio reply event per NIP-94 (kind 1063 for file metadata)
        var builder = NDKEventBuilder(ndk: nostrManager.ndk)
            .content(transcription) // NIP-94 uses content for description
            .kind(1063) // NIP-94 file metadata event
            .tag(["url", blossomURL.absoluteString])
            .tag(["m", "audio/m4a"]) // MIME type
            .tag(["x", calculateSHA256(of: audioData)]) // File hash
            .tag(["size", String(audioData.count)]) // File size in bytes
            .tag(["e", replyToEvent.id, "", "reply"]) // Reply to the text event
            .tag(["e", conversation.id, "", "root"]) // Root conversation reference
            .tag(["a", project.addressableId]) // Reference the project
        
        // Add optional tags
        if !waveformString.isEmpty {
            builder = builder
                .tag(["waveform", waveformString])
                .tag(["duration", String(Int(duration))])
        }
        
        // Add agent mentions using p tags
        for agentPubkey in selectedAgents {
            builder = builder.tag(["p", agentPubkey])
        }
        
        let audioEvent = try await builder.build()
        try await nostrManager.ndk.publish(audioEvent)
    }
    
    private func calculateSHA256(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Supporting Views

struct WaveformView: View {
    let amplitudes: [Float]
    let isRecording: Bool
    
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<40, id: \.self) { index in
                Capsule()
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: 2, height: getBarHeight(for: index))
                    .animation(.easeInOut(duration: 0.1), value: amplitudes)
            }
        }
    }
    
    private func getBarHeight(for index: Int) -> CGFloat {
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 60
        
        guard index < amplitudes.count else {
            return minHeight
        }
        
        let amplitude = amplitudes[index]
        let normalizedAmplitude = min(max(amplitude, 0), 1)
        
        if isRecording && index >= amplitudes.count - 5 {
            // Animated recent bars
            return minHeight + (maxHeight - minHeight) * CGFloat(normalizedAmplitude) * (0.5 + 0.5 * sin(Date().timeIntervalSince1970 * 10))
        }
        
        return minHeight + (maxHeight - minHeight) * CGFloat(normalizedAmplitude)
    }
}

struct AgentPillView: View {
    let agent: NDKProjectStatus.AgentStatus
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Text(agent.slug)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color(UIColor.systemGray6))
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
    }
}