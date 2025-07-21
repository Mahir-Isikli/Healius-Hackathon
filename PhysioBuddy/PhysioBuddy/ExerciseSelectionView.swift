import SwiftUI

struct ExerciseSelectionView: View {
    let poseDetector: PoseRTC
    let onExerciseSelected: (ExerciseType) -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                // Same gradient background as Welcome screen
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
                    // Header
                    VStack(spacing: 12) {
                        Text("Choose Your Exercise")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                        
                        Text("Select an exercise to begin your personalized physiotherapy session")
                            .font(.system(size: 15))
                            .foregroundColor(.black.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        
                        // Connection status
                        if poseDetector.connectionState == .connected {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(red: 0.4, green: 0.8, blue: 0.6))
                                    .frame(width: 8, height: 8)
                                Text("Ready")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.6))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.8))
                            )
                        }
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 30)
                    
                    // Exercise options - properly spaced
                    VStack(spacing: 30) {
                        // Shoulder Exercises
                        VStack(spacing: 16) {
                            // Shoulder image as squircle
                            ZStack {
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(.black.opacity(0.05))
                                    .frame(width: 120, height: 120)
                                
                                if let imagePath = Bundle.main.path(forResource: "Shoulder_Shrug", ofType: "png"),
                                   let uiImage = UIImage(contentsOfFile: imagePath) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 120, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 24))
                                } else {
                                    Image(systemName: "figure.arms.open")
                                        .font(.system(size: 40))
                                        .foregroundColor(.black.opacity(0.3))
                                }
                            }
                            
                            Text("Shoulder Exercises")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.black)
                            
                            // Horizontal exercise options
                            HStack(spacing: 12) {
                                ForEach([ExerciseType.shoulderSqueezes, ExerciseType.shoulderShrugs], id: \.self) { exercise in
                                    Button(action: {
                                        onExerciseSelected(exercise)
                                    }) {
                                        VStack(spacing: 6) {
                                            Text(exercise.displayName)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(.black)
                                                .fixedSize(horizontal: false, vertical: true)
                                            
                                            Text(description(for: exercise))
                                                .font(.system(size: 12))
                                                .foregroundColor(.black.opacity(0.6))
                                                .multilineTextAlignment(.center)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.6))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(.black.opacity(0.08), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 40)
                        }
                        
                        // Hip Mobility
                        VStack(spacing: 16) {
                            // Hip mobility image as squircle
                            ZStack {
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(.black.opacity(0.05))
                                    .frame(width: 120, height: 120)
                                
                                if let imagePath = Bundle.main.path(forResource: "Sideleg_raises", ofType: "png"),
                                   let uiImage = UIImage(contentsOfFile: imagePath) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 120, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 24))
                                } else {
                                    Image(systemName: "figure.walk")
                                        .font(.system(size: 40))
                                        .foregroundColor(.black.opacity(0.3))
                                }
                            }
                            
                            Text("Hip Mobility")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.black)
                            
                            // Single exercise option with white container
                            Button(action: {
                                onExerciseSelected(.sideLegRaises)
                            }) {
                                VStack(spacing: 6) {
                                    Text("Side Leg Raises")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.black)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    Text("Strengthen hip abductors")
                                        .font(.system(size: 12))
                                        .foregroundColor(.black.opacity(0.6))
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(.black.opacity(0.08), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 80)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    private func description(for exercise: ExerciseType) -> String {
        switch exercise {
        case .shoulderSqueezes: return "Great for posture correction"
        case .shoulderShrugs: return "Relieve shoulder tension"
        case .neckRotations: return "Release neck tension"
        case .sideLegRaises: return "Strengthen hip and leg muscles"
        }
    }
}

