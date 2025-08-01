import SwiftUI
import AVFoundation
import NDKSwift

struct VoiceMessageView: View {
    let audioEvent: NDKEvent
    let isFromCurrentUser: Bool
    let availableAgents: [NDKProjectStatus.AgentStatus]
    
    @EnvironmentObject var audioManager: AudioManager
    @State private var waveformAmplitudes: [Float] = []
    @State private var duration: TimeInterval = 0
    @State private var isDragging = false
    
    private var audioURL: String {
        // For NIP-94 events, extract URL from tags
        if audioEvent.kind == 1063 {
            return audioEvent.tags.first(where: { $0.first == "url" && $0.count > 1 })?[1] ?? ""
        }
        // Fallback to content for legacy NIP-A0 events
        return audioEvent.content
    }
    
    private var isPlaying: Bool {
        audioManager.currentlyPlayingId == audioEvent.id
    }
    
    private var isLoading: Bool {
        audioManager.isLoadingAudio && audioManager.currentlyPlayingId == audioEvent.id
    }
    
    private var progress: Double {
        isPlaying ? audioManager.playbackProgress : 0
    }
    
    private var formattedDuration: String {
        if isPlaying && audioManager.totalPlaybackDuration > 0 {
            return formatTime(audioManager.currentPlaybackTime)
        }
        return formatTime(duration > 0 ? duration : extractDurationFromEvent())
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func extractDurationFromEvent() -> TimeInterval {
        // For NIP-94 events, extract from duration tag
        if audioEvent.kind == 1063 {
            if let durationTag = audioEvent.tags.first(where: { $0.first == "duration" && $0.count > 1 }) {
                return TimeInterval(durationTag[1]) ?? 0
            }
        } else {
            // Legacy NIP-A0: Extract duration from imeta tag
            if let imetaTag = audioEvent.tags.first(where: { $0.first == "imeta" }),
               let durationString = imetaTag.first(where: { $0.contains("duration") })?.split(separator: " ").last {
                return TimeInterval(String(durationString)) ?? 0
            }
        }
        return 0
    }
    
    private func extractWaveform() -> [Float] {
        // For NIP-94 events, extract from waveform tag
        if audioEvent.kind == 1063 {
            if let waveformTag = audioEvent.tags.first(where: { $0.first == "waveform" && $0.count > 1 }) {
                return waveformTag[1].split(separator: " ").compactMap { Float($0) }
            }
        } else {
            // Legacy NIP-A0: Extract waveform from imeta tag
            if let imetaTag = audioEvent.tags.first(where: { $0.first == "imeta" }),
               let waveformString = imetaTag.first(where: { $0.contains("waveform") }) {
                let waveformPart = waveformString.replacingOccurrences(of: "waveform ", with: "")
                return waveformPart.split(separator: " ").compactMap { Float($0) }
            }
        }
        return []
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Show avatar for all non-current-user messages
            if !isFromCurrentUser {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(audioEvent.pubkey.prefix(2)).uppercased())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    )
            }
            
            if isFromCurrentUser {
                Spacer()
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Voice message bubble
                HStack(spacing: 12) {
                    // Play/pause button
                    Button(action: togglePlayback) {
                        ZStack {
                            Circle()
                                .fill(isFromCurrentUser ? Color.white.opacity(0.3) : Color.blue)
                                .frame(width: 36, height: 36)
                            
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: isFromCurrentUser ? .white : .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: isPlaying && audioManager.audioPlayer?.isPlaying == true ? "pause.fill" : "play.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(isFromCurrentUser ? .white : .white)
                            }
                        }
                    }
                    .disabled(isLoading)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Waveform or progress bar
                        if waveformAmplitudes.isEmpty {
                            // Simple progress bar if no waveform with drag gesture
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 3)
                                        .cornerRadius(1.5)
                                    
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: geometry.size.width * progress, height: 3)
                                        .cornerRadius(1.5)
                                }
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            if isPlaying {
                                                isDragging = true
                                                let progress = min(max(0, value.location.x / geometry.size.width), 1)
                                                audioManager.seekAudio(to: progress)
                                            }
                                        }
                                        .onEnded { _ in
                                            isDragging = false
                                        }
                                )
                            }
                            .frame(height: 20)
                        } else {
                            // Waveform visualization with drag gesture
                            GeometryReader { geometry in
                                HStack(spacing: 2) {
                                    ForEach(0..<min(waveformAmplitudes.count, 40), id: \.self) { index in
                                        Capsule()
                                            .fill(getWaveformColor(for: index))
                                            .frame(width: 2, height: getWaveformHeight(for: index))
                                    }
                                }
                                .frame(height: 20)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            if isPlaying {
                                                isDragging = true
                                                let progress = min(max(0, value.location.x / geometry.size.width), 1)
                                                audioManager.seekAudio(to: progress)
                                            }
                                        }
                                        .onEnded { _ in
                                            isDragging = false
                                        }
                                )
                            }
                            .frame(height: 20)
                        }
                        
                        // Duration
                        Text(formattedDuration)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isFromCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isFromCurrentUser ? .white : .primary)
                .cornerRadius(16)
                
                // Timestamp
                Text(Date(timeIntervalSince1970: TimeInterval(audioEvent.createdAt)), style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray)
                
                // Error message if any
                if let error = audioManager.error, isPlaying {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: isFromCurrentUser ? .trailing : .leading)
            
            if !isFromCurrentUser {
                Spacer()
            }
        }
        .onAppear {
            waveformAmplitudes = extractWaveform()
            duration = extractDurationFromEvent()
        }
    }
    
    private func getWaveformColor(for index: Int) -> Color {
        let progressIndex = Int(Double(waveformAmplitudes.count) * progress)
        return index < progressIndex ? Color.white : Color.white.opacity(0.5)
    }
    
    private func getWaveformHeight(for index: Int) -> CGFloat {
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 20
        
        guard index < waveformAmplitudes.count else {
            return minHeight
        }
        
        let amplitude = waveformAmplitudes[index]
        let normalizedAmplitude = min(max(amplitude, 0), 1)
        
        return minHeight + (maxHeight - minHeight) * CGFloat(normalizedAmplitude)
    }
    
    private func togglePlayback() {
        Task {
            await audioManager.toggleAudioPlayback(for: audioURL, eventId: audioEvent.id)
        }
    }
}