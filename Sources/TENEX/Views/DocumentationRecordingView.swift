import SwiftUI
import NDKSwift
import AVFoundation
import CryptoKit

struct DocumentationRecordingView: View {
    let project: NDKProject
    let onDocumentationCreated: () -> Void
    
    @Environment(\.dismiss) var dismiss
    @Environment(NostrManager.self) private var nostrManager
    @StateObject private var audioManager = AudioManager.shared
    
    @State private var isRecording = false
    @State private var isPaused = false
    @State private var transcribedText = ""
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isProcessing = false
    @State private var waveformAmplitudes: [Float] = []
    @State private var recordedAudioURL: URL?
    @State private var hasStartedRecording = false
    
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color.black
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .edgesIgnoringSafeArea(.all)
                
                // Background waveform
                if hasStartedRecording {
                    VStack {
                        Spacer()
                        WaveformView(amplitudes: waveformAmplitudes, isRecording: isRecording && !isPaused, isPaused: isPaused)
                            .frame(height: 120)
                            .opacity(0.3)
                            .padding(.horizontal, 40)
                        Spacer()
                    }
                }
                
                VStack(spacing: 0) {
                    // Subtle recording status at top
                    if hasStartedRecording {
                        HStack {
                            Circle()
                                .fill(isRecording && !isPaused ? Color.red : (isPaused ? Color.orange : Color.gray))
                                .frame(width: 8, height: 8)
                                .opacity(isRecording && !isPaused ? 1.0 : 0.6)
                            
                            Text(isRecording && !isPaused ? "Recording • \(formattedDuration)" : (isPaused ? "Paused • \(formattedDuration)" : "Stopped • \(formattedDuration)"))
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.top, 60)
                    }
                    
                    Spacer()
                    
                    // Centered transcription
                    if !transcribedText.isEmpty {
                        ScrollView {
                            Text(transcribedText)
                                .font(.system(size: 18, weight: .regular))
                                .lineLimit(nil)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxHeight: 300)
                        .animation(.easeInOut(duration: 0.3), value: transcribedText)
                    } else if hasStartedRecording {
                        Text("Listening...")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    
                    Spacer()
                    
                    // Control buttons
                    HStack(spacing: 50) {
                        // Cancel button
                        Button(action: {
                            stopRecording()
                            dismiss()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 60, height: 60)
                                Image(systemName: "xmark")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        
                        // Record/Pause button
                        Button(action: {
                            if !hasStartedRecording {
                                startRecording()
                            } else if isRecording {
                                pauseRecording()
                            } else {
                                resumeRecording()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(isRecording && !isPaused ? Color.red.opacity(0.9) : (isPaused ? Color.orange.opacity(0.9) : Color.red.opacity(0.9)))
                                    .frame(width: 80, height: 80)
                                    .shadow(color: (isRecording && !isPaused ? Color.red : (isPaused ? Color.orange : Color.red)).opacity(0.4), radius: 8, x: 0, y: 0)
                                
                                if !hasStartedRecording {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 24, height: 24)
                                } else if isRecording && !isPaused {
                                    HStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.white)
                                            .frame(width: 8, height: 24)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.white)
                                            .frame(width: 8, height: 24)
                                    }
                                } else {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                        .offset(x: 2)
                                }
                            }
                        }
                        .disabled(isProcessing)
                        
                        // Send button
                        Button(action: {
                            if hasStartedRecording && recordedAudioURL != nil {
                                sendDocumentation()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(hasStartedRecording && !isRecording && !isPaused && !isProcessing ? Color.blue.opacity(0.9) : Color.white.opacity(0.1))
                                    .frame(width: 60, height: 60)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(hasStartedRecording && !isRecording && !isPaused && !isProcessing ? .white : .white.opacity(0.4))
                            }
                        }
                        .disabled(!hasStartedRecording || (isRecording && !isPaused) || isProcessing || recordedAudioURL == nil)
                    }
                    .padding(.bottom, 50)
                }
                
                if isProcessing {
                    Color.black.opacity(0.5)
                        .edgesIgnoringSafeArea(.all)
                    
                    ProgressView("Creating documentation...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(12)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                // Start recording immediately when view appears
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // Small delay to ensure view is ready
                    startRecording()
                }
            }
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
                    if self.waveformAmplitudes.count > 50 {
                        self.waveformAmplitudes.removeFirst()
                    }
                }
            }
            
            isRecording = true
            hasStartedRecording = true
            
            // Start timer for duration
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingDuration += 0.1
            }
        }
    }
    
    private func pauseRecording() {
        timer?.invalidate()
        timer = nil
        audioManager.stopRecording()
        isRecording = false
        isPaused = true
    }
    
    private func resumeRecording() {
        Task {
            await audioManager.startRecordingWithFile { transcription, audioURL, amplitude in
                if !transcription.isEmpty {
                    // Append new transcription to existing
                    if !self.transcribedText.isEmpty {
                        self.transcribedText += " " + transcription
                    } else {
                        self.transcribedText = transcription
                    }
                }
                self.recordedAudioURL = audioURL
                
                if let amp = amplitude {
                    self.waveformAmplitudes.append(amp)
                    if self.waveformAmplitudes.count > 50 {
                        self.waveformAmplitudes.removeFirst()
                    }
                }
            }
            
            isRecording = true
            isPaused = false
            
            // Resume timer for duration
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingDuration += 0.1
            }
        }
    }
    
    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        audioManager.stopRecording()
        isRecording = false
        isPaused = false
    }
    
    private func sendDocumentation() {
        guard let audioURL = recordedAudioURL else { return }
        
        isProcessing = true
        
        Task {
            await createDocumentationRequest(
                transcript: transcribedText,
                audioURL: audioURL,
                duration: recordingDuration,
                waveformAmplitudes: waveformAmplitudes
            )
            
            await MainActor.run {
                isProcessing = false
                onDocumentationCreated()
                dismiss()
            }
        }
    }
    
    private func createDocumentationRequest(
        transcript: String,
        audioURL: URL,
        duration: TimeInterval,
        waveformAmplitudes: [Float]
    ) async {
        do {
            // Format the content with the transcript
            let content = "Save this transcription in a project document. <transcript>\(transcript)</transcript>."
            
            // Find project manager agent
            var mentionedAgents: [String] = []
            let projectManagerAgent = nostrManager.getAvailableAgents(for: project.addressableId)
                .first { $0.slug == "project-manager" }
            
            if let projectManager = projectManagerAgent {
                mentionedAgents.append(projectManager.id)
            }
            
            // Create new conversation
            let conversation = try await nostrManager.createConversation(
                in: project,
                title: nil,
                content: content,
                mentionedAgentPubkeys: mentionedAgents
            )
            
            // Upload audio and create audio event
            try await uploadAudioAndCreateEvent(
                audioURL: audioURL,
                conversation: conversation,
                transcription: transcript,
                duration: duration,
                waveformAmplitudes: waveformAmplitudes,
                mentionedAgentPubkeys: mentionedAgents
            )
        } catch {
            print("Failed to create documentation request: \(error)")
        }
    }
    
    private func uploadAudioAndCreateEvent(
        audioURL: URL,
        conversation: NDKConversation,
        transcription: String,
        duration: TimeInterval,
        waveformAmplitudes: [Float],
        mentionedAgentPubkeys: [String]
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
        for agentPubkey in mentionedAgentPubkeys {
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

