import SwiftUI
import WebRTC

// Custom video renderer to debug frame delivery
class DebugVideoRenderer: NSObject, RTCVideoRenderer {
    let actualRenderer: RTCMTLVideoView
    private var frameCount = 0
    
    init(actualRenderer: RTCMTLVideoView) {
        self.actualRenderer = actualRenderer
        super.init()
    }
    
    func setSize(_ size: CGSize) {
        // Always use the native size - WebRTC will handle scaling internally
        print("🎬 DEBUG: setSize called with \(size)")
        actualRenderer.setSize(size)
    }
    
    func renderFrame(_ frame: RTCVideoFrame?) {
        frameCount += 1
        // Only log every 30th frame (every 2 seconds at 15fps)  
        if frameCount % 30 == 0 {
            print("🎬 Renderer: \(frameCount) frames rendered - FORCED to 720x1280 coordinates")
        }
        
        // Always render the frame but force coordinate system consistency
        actualRenderer.renderFrame(frame)
    }
}

struct WebRTCVideoView: UIViewRepresentable {
    let track: RTCVideoTrack

    func makeUIView(context: Context) -> UIView {
        print("🎬 Creating video view for track")
        
        // Create container view
        let containerView = UIView()
        containerView.backgroundColor = UIColor.black
        
        // RTCMTLVideoView (Metal-based)
        let videoView = RTCMTLVideoView(frame: .zero)
        videoView.videoContentMode = .scaleAspectFill  // Fill to avoid black bars
        videoView.backgroundColor = UIColor.black
        videoView.translatesAutoresizingMaskIntoConstraints = false
        
        // Mirror the video horizontally for more natural selfie experience
        videoView.transform = CGAffineTransform(scaleX: -1, y: 1)
        
        containerView.addSubview(videoView)
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: containerView.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // Create debug renderer wrapper
        let debugRenderer = DebugVideoRenderer(actualRenderer: videoView)
        
        // Add track to debug renderer instead
        print("🎬 Adding track to debug renderer (wrapping MTL video view)")
        print("🎬 Track state before adding: isEnabled=\(track.isEnabled), readyState=\(track.readyState.rawValue)")
        track.add(debugRenderer)
        track.isEnabled = true
        print("🎬 Track state after adding: isEnabled=\(track.isEnabled), readyState=\(track.readyState.rawValue)")
        
        // Force a layout to ensure the view is ready
        DispatchQueue.main.async {
            containerView.layoutIfNeeded()
            print("🎬 Container view layout completed")
        }
        
        return containerView
    }
    
    func updateUIView(_ view: UIView, context: Context) { 
        print("🎬 Updating video view - track enabled: \(track.isEnabled)")
        // Don't re-add the track on updates to avoid issues
        if view.subviews.first(where: { $0 is RTCMTLVideoView }) is RTCMTLVideoView {
            // Just ensure the track is enabled
            track.isEnabled = true
            print("🎬 MTL video view found and track enabled")
        } else {
            print("❌ MTL video view not found in subviews!")
        }
    }
}
