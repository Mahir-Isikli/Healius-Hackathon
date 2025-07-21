import SwiftUI
import Lottie

struct ConnectingView: View {
    @ObservedObject var poseDetector: PoseRTC
    
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
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
            
            VStack(spacing: 48) {
                Spacer()
                
                VStack(spacing: 32) {
                    // Lottie Animation - Download a loading/connecting animation from LottieFiles
                    // Replace with: LottieView(animation: .named("loading_animation"))
                    //   .playing()
                    //   .frame(width: 180, height: 180)
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.35, green: 0.66, blue: 0.9).opacity(0.1))
                            .frame(width: 160, height: 160)
                            .scaleEffect(isAnimating ? 1.2 : 1.0)
                            .opacity(isAnimating ? 0.3 : 0.6)
                        
                        Circle()
                            .fill(Color(red: 0.35, green: 0.66, blue: 0.9).opacity(0.2))
                            .frame(width: 120, height: 120)
                            .scaleEffect(isAnimating ? 1.3 : 1.0)
                            .opacity(isAnimating ? 0.2 : 0.8)
                        
                        Circle()
                            .fill(Color(red: 0.35, green: 0.66, blue: 0.9))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "wifi")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 12) {
                        Text(connectionStatusText)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.black)
                        
                        Text(connectionSubtitle)
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 0.29, green: 0.29, blue: 0.29))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        // Connection steps
                        VStack(spacing: 8) {
                            ConnectionStep(text: "Establishing secure connection", isActive: poseDetector.connectionState == .connecting)
                            ConnectionStep(text: "Starting camera feed", isActive: poseDetector.connectionState == .connecting)
                            ConnectionStep(text: "Initializing pose detection", isActive: poseDetector.connectionState == .connecting)
                        }
                        .padding(.top, 16)
                    }
                }
                
                Spacer()
                
                if poseDetector.connectionState == .failed {
                    Button("Try Again") {
                        // Retry connection logic would go here
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(red: 0.35, green: 0.66, blue: 0.9))
                    .cornerRadius(16)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }
    
    private var connectionStatusText: String {
        switch poseDetector.connectionState {
        case .connecting: return "Connecting..."
        case .connected: return "Connected!"
        case .failed: return "Connection Failed"
        case .disconnected: return "Disconnected"
        }
    }
    
    private var connectionSubtitle: String {
        switch poseDetector.connectionState {
        case .connecting: return "Setting up your exercise session and preparing the camera feed"
        case .connected: return "Ready to start your physiotherapy session"
        case .failed: return "Unable to connect to the server. Please check your internet connection."
        case .disconnected: return "Connection lost"
        }
    }
}

// MARK: - Connection Step Component
struct ConnectionStep: View {
    let text: String
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isActive ? Color(red: 0.35, green: 0.66, blue: 0.9) : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
            
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isActive ? .black : Color(red: 0.29, green: 0.29, blue: 0.29).opacity(0.6))
            
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}