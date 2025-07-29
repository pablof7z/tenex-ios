import SwiftUI
import AVFoundation
import Speech
import NDKSwift
import Foundation

struct VoiceRecordingView: View {
    let onComplete: (String, URL, TimeInterval, [Float]) -> Void
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
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
    @FocusState private var isTextFieldFocused: Bool
    
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
                                Button(action: completeRecording) {
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
                    
                    Spacer()
                        .frame(height: 60)
                }
            }
            .navigationTitle("Voice Recording")
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
        
        onComplete(transcribedText, audioURL, recordingDuration, waveformAmplitudes)
        dismiss()
    }
}