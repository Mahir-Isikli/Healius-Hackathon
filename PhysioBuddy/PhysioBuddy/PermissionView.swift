import SwiftUI
import AVFoundation

struct PermissionView: View {
    let onPermissionGranted: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(Color(red: 0.15, green: 0.39, blue: 0.92))
            
            VStack(spacing: 16) {
                Text("Camera Access Required")
                    .font(.system(size: 22, weight: .bold))
                
                Text("We use your camera to analyze exercise form and provide real-time feedback.")
                    .font(.system(size: 17))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                Button("Allow Camera") {
                    requestCameraPermission()
                }
                .buttonStyle(PrimaryButtonStyle())
                
                Button("Not Now") {
                    onPermissionGranted()
                }
                .foregroundColor(Color(red: 0.15, green: 0.39, blue: 0.92))
            }
        }
        .padding(32)
    }
    
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                onPermissionGranted()
            }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(red: 0.15, green: 0.39, blue: 0.92))
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}