import SwiftUI
import Lottie
import AVFoundation
import AVKit

struct WelcomeView: View {
    var titleFontSize: CGFloat = 32
    var showWelcomeContent: Bool = true
    var showLaunchTransition: Bool = false
    let onContinue: () -> Void
    @State private var audioPlayer: AVAudioPlayer?
    @State private var videoPlayer: AVPlayer?
    @State private var playerLooper: AVPlayerLooper?
    @State private var audioFadeTimer: Timer?
    @State private var holdProgress: Double = 0.0
    @State private var isTransitioning: Bool = false
    
    var body: some View {
        ZStack {
            Color.clear  // Transparent to show parent's gradient
            
            VStack(spacing: 32) {
                // Welcome Video - only show when welcome content is visible
                if showWelcomeContent {
                    if let player = videoPlayer {
                        VideoPlayer(player: player)
                            .aspectRatio(1.0, contentMode: .fit) // 1:1 square aspect ratio
                            .frame(width: 320, height: 320)
                            .clipped()
                            .cornerRadius(24)
                            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    } else {
                        // Fallback while video loads
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 320, height: 320)
                            
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundColor(Color.white.opacity(0.8))
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                
                VStack(spacing: 20) {
                    Text("Healius")
                        .font(.system(size: titleFontSize, weight: .bold))
                        .foregroundColor(.black)
                        .animation(.easeInOut(duration: 0.8), value: titleFontSize)
                    
                    if showWelcomeContent {
                        Text("Your AI physiotherapy companion")
                            .font(.system(size: 17))
                            .foregroundColor(Color(red: 0.29, green: 0.29, blue: 0.29))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .transition(.opacity)
                    }
                }
                
                // Hold-to-continue button - only show when welcome content is visible
                if showWelcomeContent {
                    HoldToConfirmButton(
                        text: "Begin Healing",
                        onComplete: {
                            // Start audio fade-out immediately
                            fadeOutAudio()
                            
                            withAnimation(.easeInOut(duration: 0.5)) {
                                isTransitioning = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                onContinue()
                            }
                        },
                        onProgressUpdate: { progress in
                            holdProgress = progress
                            adjustAudioForProgress(progress)
                        }
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .opacity(isTransitioning ? 0 : 1)
        .animation(.easeInOut(duration: 0.5), value: isTransitioning)
        .onAppear {
            setupWelcomeMedia()
        }
        .onDisappear {
            stopWelcomeMedia()
        }
    }
    
    private func adjustAudioForProgress(_ progress: Double) {
        guard let player = audioPlayer else { return }
        
        // Start fading audio when progress > 0.7 (70%)
        if progress > 0.7 {
            let fadeProgress = (progress - 0.7) / 0.3 // Map 0.7-1.0 to 0-1
            let targetVolume = 0.4 * (1.0 - fadeProgress * 0.8) // Fade to 20% of original
            player.volume = Float(targetVolume)
        }
    }
    
    // MARK: - Media Functions
    private func setupWelcomeMedia() {
        setupWelcomeVideo()
        playWelcomeAudio()
    }
    
    private func setupWelcomeVideo() {
        guard let videoPath = Bundle.main.path(forResource: "Welcome_Video", ofType: "mp4") else {
            print("❌ Welcome video file not found")
            return
        }
        
        let videoURL = URL(fileURLWithPath: videoPath)
        let playerItem = AVPlayerItem(url: videoURL)
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        
        // Create looper for seamless video looping
        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        
        videoPlayer = queuePlayer
        videoPlayer?.isMuted = true // Mute video so audio can play
        videoPlayer?.play()
        
        print("🎬 Playing welcome video on loop (muted)")
    }
    
    private func playWelcomeAudio() {
        guard let audioPath = Bundle.main.path(forResource: "Welcome_Audio", ofType: "mp3") else {
            print("❌ Welcome audio file not found")
            return
        }
        
        let audioURL = URL(fileURLWithPath: audioPath)
        
        do {
            // Configure audio session for ambient playback that doesn't interfere with WebRTC
            try AVAudioSession.sharedInstance().setCategory(
                .ambient, 
                mode: .default, 
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            
            // Start with volume 0 if showing launch transition
            if showLaunchTransition {
                audioPlayer?.volume = 0.0
            } else {
                audioPlayer?.volume = 0.4
            }
            
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            // Fade in audio if coming from launch screen
            if showLaunchTransition {
                fadeInAudio()
            }
            
            print("🎵 Playing welcome audio on loop (ambient mode)")
        } catch {
            print("❌ Error playing welcome audio: \(error.localizedDescription)")
        }
    }
    
    private func stopWelcomeMedia() {
        // Stop audio fade timer
        audioFadeTimer?.invalidate()
        audioFadeTimer = nil
        
        // Stop audio
        audioPlayer?.stop()
        audioPlayer = nil
        
        // Stop video
        videoPlayer?.pause()
        videoPlayer = nil
        playerLooper = nil
        
        print("🛑 Stopped welcome media")
    }
    
    private func fadeInAudio() {
        // Gradually increase volume from 0 to 0.4 over 2 seconds
        let targetVolume: Float = 0.4
        let fadeDuration: TimeInterval = 2.0
        let fadeSteps = 40
        let stepDuration = fadeDuration / Double(fadeSteps)
        let volumeIncrement = targetVolume / Float(fadeSteps)
        
        var currentStep = 0
        
        audioFadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { timer in
            guard let player = audioPlayer else {
                timer.invalidate()
                return
            }
            
            currentStep += 1
            player.volume = volumeIncrement * Float(currentStep)
            
            if currentStep >= fadeSteps {
                player.volume = targetVolume
                timer.invalidate()
                audioFadeTimer = nil
                print("🎵 Audio fade-in complete")
            }
        }
    }
    
    private func fadeOutAudio() {
        // Gradually decrease volume to 0 over 0.8 seconds for smooth transition
        guard let player = audioPlayer else { return }
        
        let currentVolume = player.volume
        let fadeDuration: TimeInterval = 0.8
        let fadeSteps = 20
        let stepDuration = fadeDuration / Double(fadeSteps)
        let volumeDecrement = currentVolume / Float(fadeSteps)
        
        var currentStep = 0
        
        // Cancel any existing fade timer
        audioFadeTimer?.invalidate()
        
        audioFadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { timer in
            guard let player = self.audioPlayer else {
                timer.invalidate()
                return
            }
            
            currentStep += 1
            let newVolume = currentVolume - (volumeDecrement * Float(currentStep))
            player.volume = max(0, newVolume)
            
            if currentStep >= fadeSteps || player.volume <= 0 {
                player.volume = 0
                timer.invalidate()
                self.audioFadeTimer = nil
                print("🎵 Audio fade-out complete")
            }
        }
    }
}

// MARK: - Hold to Confirm Button
struct HoldToConfirmButton: View {
    let text: String
    let onComplete: () -> Void
    var onProgressUpdate: ((Double) -> Void)? = nil
    
    @State private var isPressed = false
    @State private var progress: Double = 0.0
    @State private var timer: Timer?
    @State private var currentScale: Double = 1.0
    
    private let holdDuration: Double = 2.5
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    private let hapticHeavy = UIImpactFeedbackGenerator(style: .heavy)
    
    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                // Simplified instruction - fades during interaction
                Text("Hold to commit")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.black.opacity(isPressed ? 0.2 : 0.6))
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.3), value: isPressed)
                
                // Button circle - this will scale up
                ZStack {
                    // Background circle with dramatic progressive scaling
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.8, blue: 0.6),
                                    Color(red: 0.3, green: 0.7, blue: 0.5)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 100, height: 100)
                        .scaleEffect(currentScale)
                        .shadow(
                            color: Color.black.opacity(0.3), 
                            radius: currentScale > 1.2 ? 25 : 12, 
                            x: 0, 
                            y: currentScale > 1.2 ? 12 : 6
                        )
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentScale)
                    
                    // Progress ring
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 6)
                        .frame(width: 88, height: 88)
                        .scaleEffect(currentScale)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.white, lineWidth: 6)
                        .frame(width: 88, height: 88)
                        .rotationEffect(.degrees(-90))
                        .scaleEffect(currentScale)
                        .animation(.linear(duration: 0.1), value: progress)
                    
                    // Icon with scaling
                    Image(systemName: "heart.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .scaleEffect(currentScale)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentScale)
                }
                .zIndex(10) // Ensure button is above text
                
                // Action text - fades and scales down during interaction
                Text(text)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.black.opacity(isPressed ? 0.2 : 0.8))
                    .multilineTextAlignment(.center)
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: isPressed)
            }
        }
        .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 80) {
            // Success haptic
            hapticHeavy.impactOccurred()
            onComplete()
        } onPressingChanged: { pressing in
            if pressing {
                startHold()
            } else {
                cancelHold()
            }
        }
        .onAppear {
            // Prepare haptic generators
            hapticLight.prepare()
            hapticMedium.prepare()
            hapticHeavy.prepare()
        }
    }
    
    private func startHold() {
        isPressed = true
        progress = 0.0
        currentScale = 1.0
        
        // Initial haptic
        hapticLight.impactOccurred()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            progress += 0.05 / holdDuration
            
            // Update progress callback
            onProgressUpdate?(progress)
            
            // Progressive scaling that gets bigger and bigger
            let newScale = 1.0 + (progress * 0.8) // Grows up to 1.8x size
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                currentScale = newScale
            }
            
            // Progressive haptic feedback
            if progress >= 0.25 && progress < 0.3 {
                hapticLight.impactOccurred()
            } else if progress >= 0.5 && progress < 0.55 {
                hapticMedium.impactOccurred()
            } else if progress >= 0.75 && progress < 0.8 {
                hapticMedium.impactOccurred()
            }
            
            if progress >= 1.0 {
                progress = 1.0
                timer?.invalidate()
            }
        }
    }
    
    private func cancelHold() {
        isPressed = false
        progress = 0.0
        
        // Smooth scale back down
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            currentScale = 1.0
        }
        
        timer?.invalidate()
        timer = nil
    }
}