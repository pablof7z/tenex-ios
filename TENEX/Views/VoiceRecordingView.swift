import SwiftUI
import AVFoundation
import Speech
import NDKSwift
import Foundation
import CryptoKit

struct VoiceRecordingView: View {
    // Project context
    let project: NDKProject
    let replyToConversation: NDKConversation?
    let lastVisibleMessage: NDKEvent?
    let selectedAgents: Set<String>
    let onConversationCreated: ((NDKConversation) -> Void)?
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(NostrManager.self) private var nostrManager
    
    @StateObject private var audioManager = AudioManager.shared
    @State private var isRecording = false
    @State private var transcribedText = ""
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isProcessing = false
    @State private var waveformAmplitudes: [Float] = []
    @State private var recordedAudioURL: URL?
    @State private var isPaused = false
    @State private var hasStartedRecording = false
    @State private var isEditingTranscription = false
    @State private var editedText = ""
    @State private var showTranscription = true
    @FocusState private var isTextFieldFocused: Bool
    
    // Convenience initializers
    init(project: NDKProject, 
         replyToConversation: NDKConversation? = nil,
         lastVisibleMessage: NDKEvent? = nil,
         selectedAgents: Set<String> = [],
         onConversationCreated: ((NDKConversation) -> Void)? = nil) {
        self.project = project
        self.replyToConversation = replyToConversation
        self.lastVisibleMessage = lastVisibleMessage
        self.selectedAgents = selectedAgents
        self.onConversationCreated = onConversationCreated
    }
    
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Clean background
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Timer section
                    VStack(spacing: 36) {
                        Text(formattedDuration)
                            .font(.system(size: 72, weight: .ultraLight, design: .rounded))
                            .foregroundColor(.primary)
                            .monospacedDigit()
                            .padding(.top, 60)
                        
                        // Waveform with subtle background
                        WaveformView(
                            amplitudes: waveformAmplitudes, 
                            isRecording: isRecording, 
                            isPaused: isPaused,
                            minHeight: 3,
                            maxHeight: 50
                        )
                        .frame(height: 80)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color(UIColor.systemGray6).opacity(0.3))
                                .padding(.horizontal, 12)
                        )
                    }
                    
                    // Transcription section
                    VStack(spacing: 0) {
                        // Toggle header
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showTranscription.toggle()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Text("Transcript")
                                    .font(.system(size: 13, weight: .semibold))
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .medium))
                                    .rotationEffect(.degrees(showTranscription ? 0 : -90))
                            }
                            .foregroundColor(.secondary.opacity(0.8))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Transcription content
                        if showTranscription {
                            if isEditingTranscription {
                                // Edit mode
                                VStack(spacing: 16) {
                                    ScrollView {
                                        TextField("Edit transcription...", text: $editedText, axis: .vertical)
                                            .font(.system(size: 16))
                                            .padding(16)
                                            .focused($isTextFieldFocused)
                                            .textFieldStyle(PlainTextFieldStyle())
                                    }
                                    .frame(maxHeight: 200)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color(UIColor.systemGray6).opacity(0.5))
                                    )
                                    .padding(.horizontal, 20)
                                    
                                    // Edit buttons
                                    HStack(spacing: 16) {
                                        Button("Cancel") {
                                            cancelEdit()
                                        }
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 8)
                                        .background(Capsule().stroke(Color.secondary.opacity(0.3)))
                                        
                                        Button("Save") {
                                            saveEdit()
                                        }
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(Color.blue))
                                    }
                                }
                                .padding(.bottom, 20)
                                .transition(.scale.combined(with: .opacity))
                            } else {
                                // View mode - floating text like Apple Music lyrics
                                ScrollView {
                                    Text(transcribedText.isEmpty ? "Listening..." : transcribedText)
                                        .font(.system(size: 18, weight: .regular))
                                        .foregroundColor(transcribedText.isEmpty ? .secondary.opacity(0.6) : .primary.opacity(0.9))
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 32)
                                        .padding(.vertical, 20)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if !transcribedText.isEmpty && !isRecording {
                                                startEditing()
                                            }
                                        }
                                }
                                .frame(maxHeight: 200)
                                .overlay(alignment: .top) {
                                    if !transcribedText.isEmpty && !isRecording {
                                        Text("Tap to edit")
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.5))
                                            .padding(.top, 4)
                                    }
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .scale.combined(with: .opacity)
                                ))
                            }
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showTranscription)
                    
                    Spacer()
                    
                    // Recording controls - simple pause/send buttons
                    HStack {
                        // Pause button on the left
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            handlePauseResume()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color(UIColor.secondarySystemBackground))
                                    .frame(width: 60, height: 60)
                                    .overlay(
                                        Circle()
                                            .stroke(Color(UIColor.separator).opacity(0.2), lineWidth: 0.5)
                                    )
                                
                                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                        }
                        .opacity(hasStartedRecording ? 1 : 0.3)
                        .disabled(!hasStartedRecording || isProcessing)
                        
                        Spacer()
                        
                        // Send button on the right
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            completeRecording()
                        }) {
                            ZStack {
                                if isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(width: 60, height: 60)
                                        .background(Circle().fill(Color.blue.opacity(0.6)))
                                } else {
                                    Circle()
                                        .fill(LinearGradient(
                                            colors: [Color.blue, Color.blue.opacity(0.9)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                        .frame(width: 60, height: 60)
                                    
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .opacity(!transcribedText.isEmpty && recordedAudioURL != nil ? 1 : 0.3)
                        .disabled(transcribedText.isEmpty || recordedAudioURL == nil || isEditingTranscription || isProcessing)
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 50)
                }
            }
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color(UIColor.secondarySystemBackground)))
                    }
                }
            }
        }
        .onAppear {
            requestPermissions()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                startRecording()
            }
        }
        .onDisappear {
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
    
    private func startRecording() {
        Task {
            transcribedText = ""
            waveformAmplitudes = []
            recordingDuration = 0
            
            await audioManager.startRecordingWithFile { transcription, audioURL, amplitude in
                if !transcription.isEmpty {
                    self.transcribedText = transcription
                }
                self.recordedAudioURL = audioURL
                
                if let amp = amplitude {
                    self.waveformAmplitudes.append(amp)
                    if self.waveformAmplitudes.count > 100 {
                        self.waveformAmplitudes.removeFirst()
                    }
                }
            }
            
            isRecording = true
            hasStartedRecording = true
            isPaused = false
            
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
    
    private func handlePauseResume() {
        if isPaused {
            audioManager.resumeRecording()
            isPaused = false
        } else {
            audioManager.pauseRecording()
            isPaused = true
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
    
    private func completeRecording() {
        guard let audioURL = recordedAudioURL,
              !transcribedText.isEmpty else { return }
        
        isProcessing = true
        stopRecording()
        
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
            to: "https://blossom.primal.net",
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
        
        // Upload audio file to blossom server
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
        
        // Create audio event as a reply
        var builder = NDKEventBuilder(ndk: nostrManager.ndk)
            .content(transcription)
            .kind(1063)
            .tag(["url", blossomURL.absoluteString])
            .tag(["m", "audio/m4a"])
            .tag(["x", calculateSHA256(of: audioData)])
            .tag(["size", String(audioData.count)])
            .tag(["e", replyToEvent.id, "", "reply"]) // Reply to the text event
            .tag(["e", conversation.id, "", "root"]) // Root conversation
            .tag(["a", project.addressableId])
        
        // Add optional tags
        if !waveformString.isEmpty {
            builder = builder
                .tag(["waveform", waveformString])
                .tag(["duration", String(Int(duration))])
        }
        
        // Add agent mentions
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