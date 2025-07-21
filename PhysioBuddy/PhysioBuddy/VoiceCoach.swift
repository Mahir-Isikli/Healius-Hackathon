import Foundation
import OpenAIRealtime
import SwiftUI
import Combine
import AVFoundation

class VoiceCoach: ObservableObject {
    private var conversation: Conversation?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isListening = false
    @Published var isConnected = false
    @Published var lastResponse: String = ""
    @Published var connectionError: String?
    
    private let apiKey: String
    
    // Audio session management
    private var audioSessionConfigured = false
    private var observersRegistered = false
    private var lastRouteChangeTime = Date()
    
    // Throttling properties
    private var lastUpdateTime: Date = Date()
    private var lastRepCount: Int = 0
    private var lastPhase: String = ""
    private var lastFormCorrectionTime: Date = Date()
    private let minimumUpdateInterval: TimeInterval = 5.0 // 5 seconds between updates
    private let repCompletionDelay: TimeInterval = 1.5 // 1.5 seconds after rep completion
    private let formCorrectionInterval: TimeInterval = 8.0 // 8 seconds between form corrections
    
    init() {
        // Try multiple ways to load API key
        var foundApiKey: String = ""
        
        // Method 1: From Info.plist
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String, !apiKey.isEmpty {
            foundApiKey = apiKey
            print("✅ VoiceCoach: Found API key in Info.plist")
        }
        // Method 2: From build settings (preprocessor macros)
        else if let apiKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String, !apiKey.isEmpty {
            foundApiKey = apiKey
            print("✅ VoiceCoach: Found API key in build settings")
        }
        // Method 3: From environment variables
        else if let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty {
            foundApiKey = apiKey
            print("✅ VoiceCoach: Found API key in environment")
        }
        else {
            // TEMPORARY: Add your actual API key here for testing
            // foundApiKey = "sk-your-actual-api-key-here"
            print("❌ OPENAI_API_KEY not found in any location")
            print("💡 Add OPENAI_API_KEY to:")
            print("   1. Xcode Build Settings > User-Defined")
            print("   2. Target > Build Settings > Preprocessor Macros") 
            print("   3. Info.plist with value: $(OPENAI_API_KEY)")
        }
        
        self.apiKey = foundApiKey
        setupConversation()
    }
    
    private func setupConversation() {
        conversation = Conversation(authToken: apiKey)
        
        // Configure the conversation when connected
        Task {
            try? await conversation?.whenConnected {
                try await self.conversation?.updateSession { session in
                    session.instructions = """
                    You are PhysioBuddy, an AI physiotherapy coach helping users with exercise form and motivation. 
                    
                    Your role:
                    - Provide encouraging feedback on exercise performance
                    - Give clear, concise form corrections
                    - Motivate users to continue their exercise routine
                    - Keep responses brief (1-2 sentences max) since this is real-time audio
                    - Be supportive and professional
                    
                    Current context: The user is doing physiotherapy exercises and you'll receive updates about their performance including rep count, form score, and specific feedback messages.
                    
                    Respond in a encouraging, coach-like manner with brief, actionable advice.
                    """
                    session.inputAudioTranscription = Session.InputAudioTranscription()
                }
            }
        }
    }
    
    func startVoiceCoaching() {
        guard let conversation = conversation else {
            print("❌ VoiceCoach: Conversation not initialized")
            DispatchQueue.main.async {
                self.connectionError = "Failed to initialize voice coach"
                self.isListening = false
                self.isConnected = false
            }
            return
        }
        
        Task {
            do {
                // Configure audio session before starting
                try setupAudioSession()
                
                try await conversation.startListening()
                await MainActor.run {
                    self.isListening = true
                    self.isConnected = true
                    self.connectionError = nil
                }
                print("🎤 VoiceCoach: Started listening")
                
            } catch {
                print("❌ VoiceCoach: Failed to start listening: \(error)")
                await MainActor.run {
                    self.connectionError = "Failed to start voice coaching: \(error.localizedDescription)"
                    self.isListening = false
                    self.isConnected = false
                }
            }
        }
    }
    
    private func setupAudioSession() throws {
        // Prevent multiple configurations
        guard !audioSessionConfigured else {
            print("⚠️ VoiceCoach: Audio session already configured, skipping")
            return
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        
        // Set up interruption notifications only once
        if !observersRegistered {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioSessionInterruption),
                name: AVAudioSession.interruptionNotification,
                object: audioSession
            )
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioSessionRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: audioSession
            )
            
            observersRegistered = true
            print("✅ VoiceCoach: Audio observers registered")
        }
        
        // Configure audio session with options to prevent self-interruption
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [
                .defaultToSpeaker,
                .allowBluetooth,
                .allowBluetoothA2DP,
                .allowAirPlay,
                .mixWithOthers,          // Allow mixing with other audio
                .duckOthers              // Lower other audio when speaking
            ]
        )
        
        // Set preferred sample rate for better quality
        try audioSession.setPreferredSampleRate(44100.0)
        try audioSession.setPreferredIOBufferDuration(0.02) // 20ms buffer
        
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        audioSessionConfigured = true
        print("✅ VoiceCoach: Audio session configured successfully")
    }
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("🔇 VoiceCoach: Audio session interrupted - pausing")
            Task {
                await MainActor.run {
                    self.isListening = false
                }
            }
            
        case .ended:
            print("🔊 VoiceCoach: Audio session interruption ended")
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // Resume audio session
                Task {
                    do {
                        try AVAudioSession.sharedInstance().setActive(true)
                        // Restart listening if conversation is still available
                        if let conversation = conversation {
                            try await conversation.startListening()
                            await MainActor.run {
                                self.isListening = true
                            }
                        }
                        print("✅ VoiceCoach: Audio session resumed after interruption")
                    } catch {
                        print("❌ VoiceCoach: Failed to resume after interruption: \(error)")
                        await MainActor.run {
                            self.connectionError = "Audio session interrupted: \(error.localizedDescription)"
                        }
                    }
                }
            }
            
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioSessionRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        // Debounce route changes - ignore if too frequent
        let now = Date()
        let timeSinceLastChange = now.timeIntervalSince(lastRouteChangeTime)
        guard timeSinceLastChange > 0.5 else {
            print("🔇 VoiceCoach: Ignoring rapid route change (debouncing)")
            return
        }
        lastRouteChangeTime = now
        
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            print("🔄 VoiceCoach: Audio device changed - \(reason)")
            // Only log, don't reconfigure - our session supports multiple outputs
        case .categoryChange:
            print("⚠️ VoiceCoach: Audio category changed externally")
            // Reset our configuration flag if category was changed by another app
            audioSessionConfigured = false
        case .override:
            print("🔄 VoiceCoach: Audio route overridden")
            // Only log, don't reconfigure
        default:
            print("🔄 VoiceCoach: Audio route change reason: \(reason)")
            break
        }
    }
    
    func stopVoiceCoaching() {
        Task {
            await conversation?.stopListening()
            
            // Remove audio session observers only if they were registered
            if observersRegistered {
                NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
                NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
                observersRegistered = false
            }
            
            // Deactivate audio session
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                audioSessionConfigured = false
                print("✅ VoiceCoach: Audio session deactivated")
            } catch {
                print("⚠️ VoiceCoach: Failed to deactivate audio session: \(error)")
            }
            
            await MainActor.run {
                self.isListening = false
                self.isConnected = false
            }
            print("🔇 VoiceCoach: Stopped listening")
        }
    }
    
    deinit {
        // Clean up observers when the object is deallocated
        if observersRegistered {
            NotificationCenter.default.removeObserver(self)
            print("🧹 VoiceCoach: Cleaned up observers")
        }
    }
    
    func sendExerciseUpdate(exercise: String, repCount: Int, formScore: Double, phase: String, feedbackMessages: [String]) {
        guard let conversation = conversation, isConnected else {
            print("⚠️ VoiceCoach: Not connected, skipping exercise update")
            return
        }
        
        let currentTime = Date()
        let timeSinceLastUpdate = currentTime.timeIntervalSince(lastUpdateTime)
        
        // Determine if we should send an update based on context
        let shouldSendUpdate = shouldProvideUpdate(
            currentTime: currentTime,
            timeSinceLastUpdate: timeSinceLastUpdate,
            repCount: repCount,
            phase: phase,
            formScore: formScore,
            feedbackMessages: feedbackMessages
        )
        
        guard shouldSendUpdate else {
            print("🔇 VoiceCoach: Skipping update - throttling active")
            return
        }
        
        // Update tracking variables
        lastUpdateTime = currentTime
        lastRepCount = repCount
        lastPhase = phase
        
        // Update form correction time if this is a form-related update
        let poorForm = formScore < 65.0
        let hasFormFeedback = !feedbackMessages.isEmpty
        if poorForm || hasFormFeedback {
            lastFormCorrectionTime = currentTime
        }
        
        let feedbackText = feedbackMessages.isEmpty ? "form looks good" : feedbackMessages.joined(separator: ", ")
        
        let exerciseUpdateMessage = """
        Exercise Update: 
        - Exercise: \(exercise)
        - Reps completed: \(repCount)
        - Form score: \(Int(formScore))%
        - Current phase: \(phase)
        - Feedback: \(feedbackText)
        
        Please provide brief encouraging feedback or form corrections.
        """
        
        Task {
            do {
                try await conversation.send(from: .user, text: exerciseUpdateMessage)
                print("📤 VoiceCoach: Sent exercise update")
            } catch {
                print("❌ VoiceCoach: Failed to send exercise update: \(error)")
            }
        }
    }
    
    private func shouldProvideUpdate(currentTime: Date, timeSinceLastUpdate: TimeInterval, repCount: Int, phase: String, formScore: Double, feedbackMessages: [String]) -> Bool {
        // Always provide feedback for first update
        if lastUpdateTime == Date(timeIntervalSince1970: 0) {
            return true
        }
        
        // Rep completion - wait a moment after rep finishes, then provide feedback
        let repCompleted = repCount > lastRepCount
        if repCompleted && timeSinceLastUpdate >= repCompletionDelay {
            print("📈 VoiceCoach: Rep completed (\(lastRepCount) → \(repCount))")
            return true
        }
        
        // Phase transition - provide guidance when moving between exercise phases
        let phaseChanged = phase != lastPhase && !phase.isEmpty && !lastPhase.isEmpty
        if phaseChanged && timeSinceLastUpdate >= 2.0 {
            print("🔄 VoiceCoach: Phase transition (\(lastPhase) → \(phase))")
            return true
        }
        
        // Form correction needed - only for significantly poor form
        let timeSinceLastFormCorrection = currentTime.timeIntervalSince(lastFormCorrectionTime)
        let veryPoorForm = formScore < 65.0
        let criticalFeedback = feedbackMessages.contains { msg in
            msg.lowercased().contains("stop") || 
            msg.lowercased().contains("danger") || 
            msg.lowercased().contains("incorrect")
        }
        
        if (veryPoorForm || criticalFeedback) && timeSinceLastFormCorrection >= formCorrectionInterval {
            print("⚠️ VoiceCoach: Form correction needed (score: \(Int(formScore))%)")
            return true
        }
        
        // Motivational update for good progress (less frequent)
        let goodForm = formScore >= 80.0
        if goodForm && repCount > 0 && timeSinceLastUpdate >= minimumUpdateInterval * 2 {
            print("💪 VoiceCoach: Motivational update for good progress")
            return true
        }
        
        // Minimum interval check for general updates (only if something significant happened)
        if timeSinceLastUpdate >= minimumUpdateInterval && (repCount > lastRepCount || formScore < 75.0) {
            print("⏰ VoiceCoach: Minimum interval reached with significant change")
            return true
        }
        
        return false
    }
    
    func sendMotivationalPrompt() {
        guard let conversation = conversation, isConnected else {
            print("⚠️ VoiceCoach: Not connected, skipping motivational prompt")
            return
        }
        
        let motivationalPrompts = [
            "Give me some quick motivation to continue my exercise",
            "How am I doing with my physiotherapy routine?",
            "Any tips to improve my form?",
            "Encourage me to keep going with my exercises"
        ]
        
        let randomPrompt = motivationalPrompts.randomElement() ?? motivationalPrompts[0]
        
        Task {
            do {
                try await conversation.send(from: .user, text: randomPrompt)
                print("📤 VoiceCoach: Sent motivational prompt")
            } catch {
                print("❌ VoiceCoach: Failed to send motivational prompt: \(error)")
            }
        }
    }
    
    func sendUserMessage(_ message: String) {
        guard let conversation = conversation, isConnected else {
            print("⚠️ VoiceCoach: Not connected, cannot send user message")
            return
        }
        
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ VoiceCoach: Cannot send empty message")
            return
        }
        
        Task {
            do {
                try await conversation.send(from: .user, text: message)
                print("📤 VoiceCoach: Sent user message: \(message.prefix(50))...")
            } catch {
                print("❌ VoiceCoach: Failed to send user message: \(error)")
                await MainActor.run {
                    self.connectionError = "Failed to send message: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func enableLiveUpdates() {
        // OpenAI Realtime API handles live updates internally
        // No additional setup needed for this implementation
    }
}

extension VoiceCoach {
    var hasActiveConversation: Bool {
        return conversation != nil && isConnected
    }
}