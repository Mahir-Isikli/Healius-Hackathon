import SwiftUI

struct ContentView: View {
    @ObservedObject var poseDetector: PoseRTC
    let onStopSession: () -> Void
    @State private var showExerciseSelector = false
    @State private var coordinatesStabilized = false
    @State private var currentFeedbackMessage: String = ""
    @StateObject private var voiceCoach = VoiceCoach()
    @State private var lastExerciseUpdateTime: Date = Date()
    @State private var showVoiceCoachToggle = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient - Healing aesthetic from 3D illustration
                LinearGradient(
                    colors: [
                        Color(red: 0.91, green: 0.83, blue: 0.81), // #E8D3CE - Warm beige
                        Color(red: 0.81, green: 0.78, blue: 0.83), // #CEC8D4 - Soft purple-gray  
                        Color(red: 0.996, green: 0.86, blue: 0.75) // #FEDBBF - Peachy cream
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top Stats Overlay - smaller
                    topStatsOverlay
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .zIndex(10)
                    
                    Spacer(minLength: 16)
                    
                    // Video Feed Container - bigger, less padding
                    videoFeedContainer
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    
                    Spacer(minLength: 16)
                    
                    // Bottom Controls
                    bottomControlsPanel
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
            }
        }
        .onChange(of: poseDetector.latestKeypointData) { _, newData in
            // Force coordinates to be stabilized immediately - no delay needed
            if newData != nil && !coordinatesStabilized {
                print("🎬 ContentView: Keypoint data received, FORCING immediate stabilization")
                coordinatesStabilized = true // Force immediate stabilization
            }
            
            // Update feedback message with animation
            if let data = newData,
               let analysis = data.exerciseAnalysis,
               !analysis.feedbackMessages.isEmpty {
                let newMessage = analysis.feedbackMessages.first ?? ""
                if newMessage != currentFeedbackMessage {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentFeedbackMessage = newMessage
                    }
                }
                
                // Send exercise updates to voice coach every 3 seconds
                let now = Date()
                if voiceCoach.isConnected && now.timeIntervalSince(lastExerciseUpdateTime) > 3.0 {
                    voiceCoach.sendExerciseUpdate(
                        exercise: poseDetector.selectedExercise.displayName,
                        repCount: analysis.repCount,
                        formScore: analysis.formScore,
                        phase: analysis.phase,
                        feedbackMessages: analysis.feedbackMessages
                    )
                    lastExerciseUpdateTime = now
                }
            }
        }
        .sheet(isPresented: $showExerciseSelector) {
            ExerciseSelectorSheet(
                currentExercise: poseDetector.selectedExercise,
                onExerciseSelected: { exercise in
                    poseDetector.selectedExercise = exercise
                    coordinatesStabilized = false // Reset for new exercise
                    poseDetector.startSession()
                    
                    // Notify voice coach about exercise change
                    if voiceCoach.isConnected {
                        voiceCoach.sendExerciseUpdate(
                            exercise: exercise.displayName,
                            repCount: 0,
                            formScore: 0,
                            phase: "starting",
                            feedbackMessages: ["Starting \(exercise.displayName)"]
                        )
                    }
                    
                    showExerciseSelector = false
                }
            )
        }
        .onDisappear {
            coordinatesStabilized = false
            voiceCoach.stopVoiceCoaching()
        }
        .alert("Voice Coach Error", isPresented: .constant(voiceCoach.connectionError != nil)) {
            Button("OK") {
                voiceCoach.connectionError = nil
            }
        } message: {
            Text(voiceCoach.connectionError ?? "")
        }
    }
    
    // MARK: - Top Stats Overlay
    private var topStatsOverlay: some View {
        HStack {
            // Back button on the left
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    // Pause the session instead of stopping to keep connection alive
                    poseDetector.pauseSession()
                    onStopSession()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.white)
                    )
            }
            
            Spacer()
            
            // Voice Coach Toggle
            Button(action: {
                if voiceCoach.isConnected {
                    voiceCoach.stopVoiceCoaching()
                } else {
                    voiceCoach.startVoiceCoaching()
                }
            }) {
                Image(systemName: voiceCoach.isConnected ? "mic.fill" : "mic.slash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(voiceCoach.isConnected ? .white : .black)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(voiceCoach.isConnected ? Color(red: 0.35, green: 0.66, blue: 0.9) : Color.white)
                    )
            }
            
            Spacer()
            
            // Stats on the right
            if let keypointData = poseDetector.latestKeypointData,
               let analysis = keypointData.exerciseAnalysis {
                HStack(spacing: 12) {
                    StatCard(
                        title: "Reps",
                        value: "\(analysis.repCount)",
                        color: Color(red: 0.35, green: 0.66, blue: 0.9), // #5AA9E6 sleep quality blue
                        icon: "repeat"
                    )
                    
                    StatCard(
                        title: "Form",
                        value: "\(Int(analysis.formScore))%",
                        color: formScoreColor(analysis.formScore),
                        icon: "checkmark.shield"
                    )
                }
            } else {
                // Placeholder when no data
                HStack(spacing: 12) {
                    StatCard(title: "Reps", value: "0", color: .gray, icon: "repeat")
                    StatCard(title: "Form", value: "0%", color: .gray, icon: "checkmark.shield")
                }
            }
        }
    }
    
    // MARK: - Video Feed Container
    private var videoFeedContainer: some View {
        ZStack {
            // WebRTC remote video track (processed video from server)
            if let remoteTrack = poseDetector.remoteTrack {
                WebRTCVideoView(track: remoteTrack)
                    .aspectRatio(9/16, contentMode: .fill)
                    .clipped()
            } else {
                // Fallback black background when video not ready
                Rectangle()
                    .fill(Color.black)
                    .aspectRatio(9/16, contentMode: .fill)
                    .clipped()
            }
            
            // Enhanced pose overlay - let the overlay handle coordinate mapping
            if let keypointData = poseDetector.latestKeypointData {
                PoseOverlayView(
                    keypoints: keypointData.keypoints,
                    confidence: keypointData.confidence,
                    frameSize: CGSize(width: 720, height: 1280),  // Always use consistent display space
                    exerciseType: poseDetector.selectedExercise
                )
                .aspectRatio(9/16, contentMode: .fill)
                .clipped()
            }
            
            // Exercise label overlay on video
            VStack {
                HStack {
                    Text(poseDetector.selectedExercise.displayName)
                        .font(.system(size: 15, weight: .medium)) // Body text size
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                        )
                    
                    Spacer()
                }
                .padding(16)
                
                Spacer()
                
                // Feedback message overlay at bottom of video - consistent size with animation
                HStack {
                    Spacer()
                    Text(currentFeedbackMessage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(minWidth: 120, minHeight: 44) // Consistent size
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.black.opacity(0.7))
                        )
                        .animation(.easeInOut(duration: 0.3), value: currentFeedbackMessage)
                    Spacer()
                }
                .padding(.bottom, 20)
            }
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16)) // Card border radius
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 2) // Minimal shadow
    }
    
    // MARK: - Bottom Controls Panel
    private var bottomControlsPanel: some View {
        VStack(spacing: 16) {
            // Exercise Info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Exercise")
                        .font(.system(size: 13, weight: .medium)) // Caption size
                        .foregroundColor(Color(red: 0.29, green: 0.29, blue: 0.29)) // #4A4A4A secondary text
                    
                    Text(poseDetector.selectedExercise.displayName)
                        .font(.system(size: 18, weight: .bold)) // Section header size
                        .foregroundColor(.black)
                }
                
                Spacer()
                
                // Connection Status Indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 8, height: 8)
                    
                    Text(connectionStateText)
                        .font(.system(size: 13, weight: .medium)) // Caption size
                        .foregroundColor(connectionStatusColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(connectionStatusColor.opacity(0.15))
                )
            }
            
            // Control Buttons
            HStack(spacing: 12) {
                // Stop Button
                Button(action: {
                    voiceCoach.stopVoiceCoaching()
                    poseDetector.stopSession()
                    onStopSession()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 15)) // Body text size
                    .foregroundColor(Color(red: 1.0, green: 0.7, blue: 0.78)) // #FFB3C6
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(red: 1.0, green: 0.7, blue: 0.78), lineWidth: 1)
                            )
                    )
                }
                
                // Motivation Button
                Button(action: {
                    voiceCoach.sendMotivationalPrompt()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                        Text("Motivate")
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 15)) // Body text size
                    .foregroundColor(voiceCoach.isConnected ? Color(red: 0.6, green: 0.84, blue: 0.4) : Color.gray) // #98D667
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(voiceCoach.isConnected ? Color(red: 0.6, green: 0.84, blue: 0.4) : Color.gray, lineWidth: 1)
                            )
                    )
                }
                .disabled(!voiceCoach.isConnected)
                
                // Switch Exercise Button
                Button(action: {
                    showExerciseSelector = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Switch")
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 15)) // Body text size
                    .foregroundColor(Color(red: 0.35, green: 0.66, blue: 0.9)) // #5AA9E6
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(red: 0.35, green: 0.66, blue: 0.9), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(16) // Card padding
        .background(
            RoundedRectangle(cornerRadius: 16) // Card border radius
                .fill(Color.white)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Coordinate System
    private func determineVideoFrameSize() -> CGSize {
        // Always use consistent 720x1280 coordinate system
        return CGSize(width: 720, height: 1280)
    }
    
    
    // MARK: - Helper Functions
    private var connectionStateText: String {
        switch poseDetector.connectionState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .failed: return "Failed"
        }
    }
    
    private var connectionStatusColor: Color {
        switch poseDetector.connectionState {
        case .connected: return Color(red: 0.6, green: 0.84, blue: 0.4) // #98D667
        case .connecting: return Color(red: 1.0, green: 0.7, blue: 0.78) // #FFB3C6
        case .failed: return Color(red: 1.0, green: 0.7, blue: 0.78) // #FFB3C6
        case .disconnected: return Color(red: 0.29, green: 0.29, blue: 0.29) // #4A4A4A
        }
    }
    
    private func formScoreColor(_ score: Double) -> Color {
        switch score {
        case 80...: return Color(red: 0.6, green: 0.84, blue: 0.4) // #98D667 success highlight
        case 60..<80: return Color(red: 1.0, green: 0.7, blue: 0.78) // #FFB3C6 pain level
        default: return Color(red: 1.0, green: 0.7, blue: 0.78) // #FFB3C6
        }
    }
    
    private func phaseColor(_ phase: String) -> Color {
        switch phase.lowercased() {
        case "active": return Color(red: 0.6, green: 0.84, blue: 0.4) // #98D667
        case "cooldown": return Color(red: 1.0, green: 0.7, blue: 0.78) // #FFB3C6
        case "completed": return Color(red: 0.6, green: 0.84, blue: 0.4) // #98D667
        default: return Color(red: 0.29, green: 0.29, blue: 0.29) // #4A4A4A
        }
    }
}

// MARK: - StatCard Component
struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 11, weight: .medium)) // Smaller caption
                    .foregroundColor(Color(red: 0.29, green: 0.29, blue: 0.29)) // #4A4A4A secondary text
            }
            
            Text(value)
                .font(.system(size: 16, weight: .bold)) // Much smaller value text
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12) // Smaller border radius
                .fill(Color.white)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Exercise Selector Sheet
struct ExerciseSelectorSheet: View {
    let currentExercise: ExerciseType
    let onExerciseSelected: (ExerciseType) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Switch Exercise")
                    .font(.system(size: 24, weight: .bold)) // Title size
                    .foregroundColor(.black)
                    .padding(.top)
                
                ForEach(ExerciseType.allCases, id: \.self) { exercise in
                    ExerciseOptionCard(
                        exercise: exercise,
                        isSelected: exercise == currentExercise,
                        onTap: { onExerciseSelected(exercise) }
                    )
                }
                
                Spacer()
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.92, green: 0.96, blue: 0.98), // #EAF6FB
                        Color.white
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ExerciseOptionCard: View {
    let exercise: ExerciseType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color(red: 0.35, green: 0.66, blue: 0.9) : Color(red: 0.92, green: 0.96, blue: 0.98))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon(for: exercise))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isSelected ? .white : Color(red: 0.29, green: 0.29, blue: 0.29))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.displayName)
                        .font(.system(size: 18, weight: .bold)) // Section header size
                        .foregroundColor(.black)
                    
                    Text(description(for: exercise))
                        .font(.system(size: 13)) // Caption size
                        .foregroundColor(Color(red: 0.29, green: 0.29, blue: 0.29)) // #4A4A4A
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(red: 0.6, green: 0.84, blue: 0.4)) // #98D667 success
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16) // Card border radius
                    .fill(Color.white)
                    .stroke(isSelected ? Color(red: 0.35, green: 0.66, blue: 0.9) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func icon(for exercise: ExerciseType) -> String {
        switch exercise {
        case .shoulderSqueezes: return "figure.arms.open"
        case .shoulderShrugs: return "figure.arms.open"
        case .neckRotations: return "figure.mind.and.body"
        case .sideLegRaises: return "figure.walk"
        }
    }
    
    private func description(for exercise: ExerciseType) -> String {
        switch exercise {
        case .shoulderSqueezes: return "Great for posture correction"
        case .shoulderShrugs: return "Relieve shoulder tension"
        case .neckRotations: return "Release neck tension"
        case .sideLegRaises: return "Strengthen hip abductors"
        }
    }
}