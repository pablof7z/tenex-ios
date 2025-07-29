import Foundation
import AVFoundation
import Speech
import SwiftUI

@MainActor
class AudioManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = AudioManager()
    @Published var isRecording = false
    @Published var isMuted = false
    @Published var isSpeakerOn = true
    @Published var error: String?
    @Published var microphonePermissionGranted = false
    @Published var speechPermissionGranted = false
    
    // Audio playback properties
    @Published var currentlyPlayingId: String?
    @Published var playbackProgress: Double = 0
    @Published var currentPlaybackTime: TimeInterval = 0
    @Published var totalPlaybackDuration: TimeInterval = 0
    @Published var isLoadingAudio = false
    
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let synthesizer = AVSpeechSynthesizer()
    private var audioRecorder: AVAudioRecorder?
    private var speechCompletionHandler: (() -> Void)?
    
    // Audio playback
    var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var audioCache = NSCache<NSString, NSData>()
    private var downloadTasks: [String: Task<Data, Error>] = [:]
    private var playbackCompletion: (() -> Void)?
    
    // Audio session management
    private var currentAudioSessionCategory: AVAudioSession.Category = .playback
    
    // Voice activity detection
    private var silenceThreshold: Float = 0.02
    private var silenceDuration: TimeInterval = 0
    private var lastSignificantAmplitude: TimeInterval = 0
    private let maxSilenceDuration: TimeInterval = 3.0 // Auto-pause after 3 seconds of silence
    
    // Voice options for different agents
    static let voiceOptions: [(identifier: String, name: String)] = [
        ("com.apple.voice.enhanced.en-US.Ava", "Ava"),
        ("com.apple.voice.enhanced.en-US.Zoe", "Zoe"),
        ("com.apple.voice.enhanced.en-US.Allison", "Allison"),
        ("com.apple.voice.enhanced.en-US.Nathan", "Nathan"),
        ("com.apple.voice.enhanced.en-US.Noel", "Noel"),
        ("com.apple.voice.enhanced.en-US.Joelle", "Joelle"),
        ("com.apple.voice.enhanced.en-US.Tom", "Tom"),
        ("com.apple.voice.enhanced.en-US.Samantha", "Samantha")
    ]
    
    @AppStorage("agentVoicePreferences") private var agentVoicePreferencesData = Data()
    
    private var agentVoicePreferences: [String: String] {
        get {
            (try? JSONDecoder().decode([String: String].self, from: agentVoicePreferencesData)) ?? [:]
        }
        set {
            agentVoicePreferencesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
    
    override init() {
        super.init()
        synthesizer.delegate = self
        audioCache.countLimit = 50 // Cache up to 50 audio files
        setupAudioSessionObservers()
    }
    
    deinit {
        // Clean up in deinit without MainActor
        playbackTimer?.invalidate()
        for (_, task) in downloadTasks {
            task.cancel()
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    func requestPermissions() async {
        // Check microphone permission
        await checkMicrophonePermission()
        
        // Check speech recognition permission
        await checkSpeechPermission()
    }
    
    private func checkMicrophonePermission() async {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            microphonePermissionGranted = true
        case .denied:
            error = "Microphone access denied. Please enable in Settings."
            microphonePermissionGranted = false
        case .undetermined:
            await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    Task { @MainActor in
                        self.microphonePermissionGranted = granted
                        if !granted {
                            self.error = "Microphone access denied. Please enable in Settings."
                        }
                        continuation.resume()
                    }
                }
            }
        @unknown default:
            microphonePermissionGranted = false
        }
    }
    
    private func checkSpeechPermission() async {
        let status = SFSpeechRecognizer.authorizationStatus()
        
        switch status {
        case .authorized:
            speechPermissionGranted = true
        case .denied, .restricted:
            error = "Speech recognition denied. Please enable in Settings."
            speechPermissionGranted = false
        case .notDetermined:
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    Task { @MainActor in
                        self.speechPermissionGranted = (status == .authorized)
                        if status != .authorized {
                            self.error = "Speech recognition denied. Please enable in Settings."
                        }
                        continuation.resume()
                    }
                }
            }
        @unknown default:
            speechPermissionGranted = false
        }
    }
    
    func startRecording(onUpdate: @escaping (String) -> Void) async {
        guard microphonePermissionGranted && speechPermissionGranted else {
            error = "Permissions not granted"
            return
        }
        
        do {
            // Configure audio session
            try await configureAudioSession(for: .playAndRecord)
            
            // Create and configure recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                error = "Unable to create recognition request"
                return
            }
            
            recognitionRequest.shouldReportPartialResults = true
            
            // Configure audio engine
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            // Start recognition task
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, _ in
                if let result = result {
                    DispatchQueue.main.async {
                        onUpdate(result.bestTranscription.formattedString)
                    }
                }
            }
            
            isRecording = true
        } catch {
            self.error = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    func startRecordingWithFile(onUpdate: @escaping (String, URL?, Float?) -> Void) async {
        guard microphonePermissionGranted && speechPermissionGranted else {
            error = "Permissions not granted"
            return
        }
        
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording-\(Date().timeIntervalSince1970).m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            // Configure audio session
            try await configureAudioSession(for: .playAndRecord)
            
            // Create audio recorder
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            // Create and configure recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                error = "Unable to create recognition request"
                return
            }
            
            recognitionRequest.shouldReportPartialResults = true
            
            // Configure audio engine for speech recognition
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
                
                // Calculate amplitude for waveform
                let channelData = buffer.floatChannelData?[0]
                let channelDataLength = Int(buffer.frameLength)
                
                if let channelData = channelData {
                    var sum: Float = 0
                    for i in 0..<channelDataLength {
                        sum += abs(channelData[i])
                    }
                    let amplitude = sum / Float(channelDataLength)
                    
                    // Update metering and call callback
                    self.audioRecorder?.updateMeters()
                    let normalizedAmplitude = min(max(amplitude * 10, 0), 1) // Amplify and normalize
                    
                    DispatchQueue.main.async {
                        onUpdate("", audioFilename, normalizedAmplitude)
                    }
                }
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            // Start recognition task
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, _ in
                if let result = result {
                    DispatchQueue.main.async {
                        onUpdate(result.bestTranscription.formattedString, audioFilename, nil)
                    }
                }
            }
            
            isRecording = true
        } catch {
            self.error = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioRecorder?.stop()
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        
        isRecording = false
    }
    
    func pauseRecording() {
        // Pause the audio recorder
        audioRecorder?.pause()
        
        // Remove the tap before pausing to avoid conflicts
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Pause the audio engine
        audioEngine.pause()
        
        // End speech recognition audio
        recognitionRequest?.endAudio()
        
        // Cancel the recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
    }
    
    func resumeRecording() {
        // Resume the audio recorder
        audioRecorder?.record()
        
        // Resume the audio engine
        do {
            try audioEngine.start()
        } catch {
            print("Failed to resume audio engine: \(error)")
            return
        }
        
        // Create a new speech recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        
        // Re-install tap on audio input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Start a new recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Speech recognition error: \(error)")
            }
            
            if let result = result {
                // Update the transcribed text with the new results
                DispatchQueue.main.async {
                    // We need to append to existing transcription or handle it appropriately
                    // This depends on how the transcription callback is set up
                }
            }
        }
    }
    
    func toggleMute() {
        isMuted.toggle()
    }
    
    func toggleSpeaker() {
        isSpeakerOn.toggle()
    }
    
    func speakText(_ text: String, agentPubkey: String? = nil, agentSlug: String? = nil, completion: (() -> Void)? = nil) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52  // Slightly faster for more natural speech
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.9
        
        // Assign voice based on agent slug
        if let slug = agentSlug {
            // Check if we have a saved voice preference for this agent slug
            if let savedVoiceId = agentVoicePreferences[slug],
               let voice = AVSpeechSynthesisVoice(identifier: savedVoiceId) {
                utterance.voice = voice
            } else {
                // Assign a new voice based on agent slug hash
                let voice = selectVoiceForAgent(slug: slug)
                utterance.voice = voice
                
                // Save the preference
                var preferences = agentVoicePreferences
                preferences[slug] = voice.identifier
                agentVoicePreferences = preferences
            }
        } else {
            // Default voice for system messages
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        
        // Store completion handler
        speechCompletionHandler = completion
        
        synthesizer.speak(utterance)
    }
    
    private func selectVoiceForAgent(slug: String) -> AVSpeechSynthesisVoice {
        // Use a hash of the slug to consistently assign the same voice to the same agent
        let hash = slug.hashValue
        let voiceIndex = abs(hash) % Self.voiceOptions.count
        let selectedVoiceId = Self.voiceOptions[voiceIndex].identifier
        
        // Try to create voice with the selected identifier
        if let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceId) {
            return voice
        }
        
        // Fallback to default voice if specific voice not available
        return AVSpeechSynthesisVoice(language: "en-US") ?? AVSpeechSynthesisVoice(language: "en")!
    }
    
    // Allow manual voice selection for agents by slug
    func setVoiceForAgent(slug: String, voiceIdentifier: String) {
        var preferences = agentVoicePreferences
        preferences[slug] = voiceIdentifier
        agentVoicePreferences = preferences
    }
    
    // Get available voices for UI selection
    static func getAvailableVoices() -> [(identifier: String, name: String)] {
        return voiceOptions
    }
    
    // Get current voice for an agent
    func getVoiceForAgent(slug: String) -> String? {
        return agentVoicePreferences[slug]
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speechCompletionHandler?()
        speechCompletionHandler = nil
    }
    
    // MARK: - Helper
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // MARK: - Audio Playback
    
    func preloadAudio(from urlString: String) async {
        // Check if already cached
        let cacheKey = NSString(string: urlString)
        if audioCache.object(forKey: cacheKey) != nil {
            return // Already cached
        }
        
        // Check if already downloading
        if downloadTasks[urlString] != nil {
            return // Already downloading
        }
        
        // Start download task
        let task = Task<Data, Error> {
            guard let url = URL(string: urlString) else {
                throw AudioError.invalidURL
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
        downloadTasks[urlString] = task
        
        do {
            let audioData = try await task.value
            // Cache the data
            audioCache.setObject(audioData as NSData, forKey: cacheKey)
            downloadTasks.removeValue(forKey: urlString)
        } catch {
            // Silently fail for preloading
            downloadTasks.removeValue(forKey: urlString)
            print("Failed to preload audio from \(urlString): \(error)")
        }
    }
    
    func playAudio(from urlString: String, eventId: String, completion: (() -> Void)? = nil) async {
        // Stop any current playback
        if currentlyPlayingId != nil {
            stopAudioPlayback()
        }
        
        // Clear previous errors
        error = nil
        isLoadingAudio = true
        currentlyPlayingId = eventId
        playbackCompletion = completion
        
        do {
            // Check cache first
            let cacheKey = NSString(string: urlString)
            var audioData: Data
            
            if let cachedData = audioCache.object(forKey: cacheKey) as? Data {
                audioData = cachedData
            } else {
                // Check if already downloading
                if let existingTask = downloadTasks[urlString] {
                    audioData = try await existingTask.value
                } else {
                    // Download audio
                    let task = Task<Data, Error> {
                        guard let url = URL(string: urlString) else {
                            throw AudioError.invalidURL
                        }
                        let (data, _) = try await URLSession.shared.data(from: url)
                        return data
                    }
                    downloadTasks[urlString] = task
                    defer { downloadTasks.removeValue(forKey: urlString) }
                    audioData = try await task.value
                    
                    // Cache the data
                    audioCache.setObject(audioData as NSData, forKey: cacheKey)
                }
            }
            
            // Save to temporary file for playback
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(eventId).m4a")
            try audioData.write(to: tempURL)
            
            // Setup audio session for playback
            try await configureAudioSession(for: .playback)
            
            // Create and play audio player
            audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            totalPlaybackDuration = audioPlayer?.duration ?? 0
            isLoadingAudio = false
            
            // Start progress timer with weak self
            playbackTimer?.invalidate()
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updatePlaybackProgress()
            }
        } catch {
            isLoadingAudio = false
            currentlyPlayingId = nil
            self.error = "Failed to play audio: \(error.localizedDescription)"
        }
    }
    
    func pauseAudioPlayback() {
        audioPlayer?.pause()
        playbackTimer?.invalidate()
    }
    
    func resumeAudioPlayback() {
        audioPlayer?.play()
        
        // Restart progress timer with weak self
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePlaybackProgress()
        }
    }
    
    func stopAudioPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        currentlyPlayingId = nil
        playbackProgress = 0
        currentPlaybackTime = 0
        totalPlaybackDuration = 0
        playbackCompletion?()
        playbackCompletion = nil
    }
    
    func seekAudio(to progress: Double) {
        guard let player = audioPlayer else { return }
        let targetTime = player.duration * progress
        player.currentTime = targetTime
        updatePlaybackProgress()
    }
    
    func toggleAudioPlayback(for urlString: String, eventId: String) async {
        if currentlyPlayingId == eventId {
            // Currently playing this audio
            if audioPlayer?.isPlaying == true {
                pauseAudioPlayback()
            } else {
                resumeAudioPlayback()
            }
        } else {
            // Play new audio
            await playAudio(from: urlString, eventId: eventId)
        }
    }
    
    private func updatePlaybackProgress() {
        guard let player = audioPlayer else { return }
        
        currentPlaybackTime = player.currentTime
        playbackProgress = player.duration > 0 ? player.currentTime / player.duration : 0
        
        // Check if playback finished
        if !player.isPlaying && player.currentTime >= player.duration {
            stopAudioPlayback()
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopAudioPlayback()
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        self.error = "Audio decode error: \(error?.localizedDescription ?? "Unknown error")"
        stopAudioPlayback()
    }
    
    // MARK: - Text-to-Speech for Messages
    
    private var messageTTSQueue: [String] = []
    private var isPlayingMessageTTS = false
    @Published var currentTTSMessageId: String?
    @Published var isTTSPlaying = false
    
    func startMessageTTS(messages: [(id: String, content: String, author: String?)], startingFromId: String) async {
        // Stop any current TTS playback
        stopMessageTTS()
        
        // Find the starting index
        guard let startIndex = messages.firstIndex(where: { $0.id == startingFromId }) else { return }
        
        // Queue messages from the starting point
        messageTTSQueue = messages[startIndex...].map { $0.id }
        
        // Start playing
        await playNextMessageTTS(messages: messages)
    }
    
    func stopMessageTTS() {
        messageTTSQueue.removeAll()
        isPlayingMessageTTS = false
        isTTSPlaying = false
        currentTTSMessageId = nil
        synthesizer.stopSpeaking(at: .immediate)
    }
    
    private func playNextMessageTTS(messages: [(id: String, content: String, author: String?)]) async {
        guard !messageTTSQueue.isEmpty else {
            isPlayingMessageTTS = false
            isTTSPlaying = false
            currentTTSMessageId = nil
            return
        }
        
        let messageId = messageTTSQueue.removeFirst()
        guard let message = messages.first(where: { $0.id == messageId }) else {
            // Message not found, continue with next
            await playNextMessageTTS(messages: messages)
            return
        }
        
        isPlayingMessageTTS = true
        isTTSPlaying = true
        currentTTSMessageId = messageId
        
        // Speak the message
        await speakText(message.content, agentPubkey: message.author, agentSlug: nil) {
            Task { @MainActor in
                // Play next message when current one finishes
                await self.playNextMessageTTS(messages: messages)
            }
        }
    }
    
    func toggleMessageTTS(for messageId: String) -> Bool {
        if currentTTSMessageId == messageId && isTTSPlaying {
            // Currently playing this message, stop it
            stopMessageTTS()
            return false
        } else {
            // Not playing or playing a different message
            return true // Caller should start TTS
        }
    }
    
    // MARK: - Cleanup
    
    func cleanupTemporaryAudioFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in tempFiles where file.pathExtension == "m4a" {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            print("Failed to cleanup temp audio files: \(error)")
        }
    }
    
    // MARK: - Audio Session Management
    
    private func configureAudioSession(for category: AVAudioSession.Category) async throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Only change if different from current
        guard currentAudioSessionCategory != category else { return }
        
        do {
            if category == .playAndRecord {
                // Enhanced configuration for better recording quality
                try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth, .interruptSpokenAudioAndMixWithOthers])
                
                // Set preferred sample rate for better quality
                try audioSession.setPreferredSampleRate(44100)
                
                // Enable voice processing for noise reduction
                if #available(iOS 15.0, *) {
                    try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(false)
                }
            } else {
                try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetooth])
            }
            try audioSession.setActive(true)
            currentAudioSessionCategory = category
        } catch {
            print("Failed to configure audio session: \(error)")
            throw error
        }
    }
    
    private func setupAudioSessionObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Pause any ongoing playback
            if audioPlayer?.isPlaying == true {
                pauseAudioPlayback()
            }
        case .ended:
            // Resume playback if needed
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    resumeAudioPlayback()
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Pause playback when headphones are disconnected
            if audioPlayer?.isPlaying == true {
                pauseAudioPlayback()
            }
        default:
            break
        }
    }
    
    private func cleanupResources() {
        // Cancel all timers
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        // Cancel all download tasks
        for (_, task) in downloadTasks {
            task.cancel()
        }
        downloadTasks.removeAll()
        
        // Stop any ongoing audio
        audioPlayer?.stop()
        audioPlayer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        
        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // Remove observers
        NotificationCenter.default.removeObserver(self)
    }
}

enum AudioError: LocalizedError {
    case invalidURL
    case downloadFailed
    case playbackFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid audio URL"
        case .downloadFailed:
            return "Failed to download audio"
        case .playbackFailed:
            return "Failed to play audio"
        }
    }
}