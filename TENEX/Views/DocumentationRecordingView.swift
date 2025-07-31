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
                
                VStack(spacing: 32) {
                    // Title and instructions
                    VStack(spacing: 12) {
                        Text("Create Documentation")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Record your voice to create a document")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    
                    Spacer()
                    
                    // Recording visualization
                    if isRecording || hasStartedRecording {
                        VStack(spacing: 24) {
                            // Waveform
                            WaveformView(amplitudes: waveformAmplitudes, isRecording: isRecording)
                                .frame(height: 100)
                                .padding(.horizontal)
                            
                            // Duration
                            Text(formattedDuration)
                                .font(.system(size: 48, weight: .light, design: .monospaced))
                                .foregroundColor(.white)
                            
                            // Transcription preview
                            if !transcribedText.isEmpty {
                                ScrollView {
                                    Text(transcribedText)
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.9))
                                        .padding()
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(12)
                                }
                                .frame(maxHeight: 200)
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Control buttons
                    HStack(spacing: 40) {
                        // Cancel button
                        Button(action: {
                            stopRecording()
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        
                        // Record/Stop button
                        Button(action: {
                            if isRecording {
                                stopRecording()
                            } else {
                                startRecording()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(isRecording ? Color.red : Color.white)
                                    .frame(width: 80, height: 80)
                                
                                if isRecording {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white)
                                        .frame(width: 28, height: 28)
                                } else {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 70, height: 70)
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
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(hasStartedRecording && !isRecording && !isProcessing ? .blue : .white.opacity(0.3))
                        }
                        .disabled(!hasStartedRecording || isRecording || isProcessing || recordedAudioURL == nil)
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
    
    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        audioManager.stopRecording()
        isRecording = false
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

