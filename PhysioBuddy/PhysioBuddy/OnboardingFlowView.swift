import SwiftUI

struct OnboardingFlowView: View {
    @State private var appState: AppState = .launch
    @StateObject private var poseDetector = PoseRTC()
    @State private var showLaunchScreen = true
    @State private var titleFontSize: CGFloat = 48
    @State private var showWelcomeContent = false
    
    var body: some View {
        ZStack {
            // Persistent background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.91, green: 0.83, blue: 0.81), // #E8D3CE
                    Color(red: 0.81, green: 0.78, blue: 0.83), // #CEC8D4
                    Color(red: 0.996, green: 0.86, blue: 0.75) // #FEDBBF
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .zIndex(0) // Keep background below content
            
            switch appState {
            case .launch, .welcome:
                // Keep WelcomeView persistent across launch and welcome states
                WelcomeView(
                    titleFontSize: titleFontSize,
                    showWelcomeContent: showWelcomeContent,
                    showLaunchTransition: appState == .launch,
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            appState = .exerciseSelection
                        }
                    }
                )
                .transition(.identity) // Prevent any position shifts
                .onAppear {
                    if appState == .launch {
                        // First, setup the audio and video (silent)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            // Then animate the title shrinking and show welcome content
                            withAnimation(.easeInOut(duration: 0.8)) {
                                titleFontSize = 32
                                showWelcomeContent = true
                            }
                            // After animation, transition to welcome state
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                appState = .welcome
                            }
                        }
                    }
                }
                
            case .connecting:
                // Skip connecting view - go directly to exercise selection for better UX
                ExerciseSelectionView(
                    poseDetector: poseDetector,
                    onExerciseSelected: { exercise in
                        poseDetector.selectedExercise = exercise
                        poseDetector.startSession()
                        appState = .activeSession
                    }
                )
                
            case .exerciseSelection:
                ExerciseSelectionView(
                    poseDetector: poseDetector,
                    onExerciseSelected: { exercise in
                        poseDetector.selectedExercise = exercise
                        poseDetector.startSession()
                        withAnimation(.easeInOut(duration: 0.5)) {
                            appState = .activeSession
                        }
                    }
                )
                .transition(.opacity)
                
            case .activeSession:
                ContentView(
                    poseDetector: poseDetector,
                    onStopSession: { 
                        withAnimation(.easeInOut(duration: 0.5)) {
                            appState = .exerciseSelection
                        }
                    }
                )
                .environmentObject(poseDetector)
                .transition(.opacity)
            }
        }
    }
}