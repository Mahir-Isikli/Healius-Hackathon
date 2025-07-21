import SwiftUI

struct PoseOverlayView: View {
    let keypoints: [[Double]]
    let confidence: [Double]
    let frameSize: CGSize
    let exerciseType: ExerciseType
    
    // Full pose connections for exercises that need them
    private let fullPoseConnections: [(Int, Int, Color)] = [
        (15, 13, Color.white),    // Neck
        (13, 11, Color.white),    // Left shoulder
        (16, 14, Color.white),    // Right shoulder
        (14, 12, Color.white),    // Right arm
        (11, 12, Color.white),    // Torso
        (5, 11, Color.white),     // Left arm
        (6, 12, Color.white),     // Right arm
        (5, 6, Color.white),      // Chest
        (5, 7, Color.white),      // Left elbow
        (6, 8, Color.white),      // Right elbow
        (7, 9, Color.white),      // Left wrist
        (8, 10, Color.white),     // Right wrist
    ]
    
    // Upper body only connections for shoulder exercises
    private let shoulderExerciseConnections: [(Int, Int, Color)] = [
        (5, 6, Color.white),      // Chest (shoulder to shoulder)
        (5, 7, Color.white),      // Left elbow
        (6, 8, Color.white),      // Right elbow
    ]
    
    // Get appropriate connections based on exercise type
    private var poseConnections: [(Int, Int, Color)] {
        switch exerciseType {
        case .shoulderShrugs, .shoulderSqueezes:
            return shoulderExerciseConnections
        case .neckRotations, .sideLegRaises:
            return fullPoseConnections
        }
    }
    
    var body: some View {
        Canvas { context, size in
            drawPoseSkeleton(context: context, size: size)
        }
        .allowsHitTesting(false)
        .scaleEffect(x: -1, y: 1) // Mirror horizontally to match the mirrored video
    }
    
    private func drawPoseSkeleton(context: GraphicsContext, size: CGSize) {
        guard keypoints.count >= 17 else { return }
        
        let frameAspectRatio = frameSize.width / frameSize.height
        let viewAspectRatio = size.width / size.height
        
        let scaleX: Double
        let scaleY: Double
        let offsetX: Double
        let offsetY: Double
        
        if frameAspectRatio > viewAspectRatio {
            let scale = size.height / frameSize.height
            scaleX = scale
            scaleY = scale
            offsetX = (size.width - frameSize.width * scale) / 2
            offsetY = 0
        } else {
            let scale = size.width / frameSize.width
            scaleX = scale
            scaleY = scale
            offsetX = 0
            offsetY = (size.height - frameSize.height * scale) / 2
        }
        
        // Draw connections with medical-grade styling
        for (startIdx, endIdx, color) in poseConnections {
            guard startIdx < keypoints.count && endIdx < keypoints.count,
                  confidence[startIdx] > 0.3 && confidence[endIdx] > 0.3 else { continue }
            
            let startPoint = CGPoint(
                x: keypoints[startIdx][0] * scaleX + offsetX,
                y: keypoints[startIdx][1] * scaleY + offsetY
            )
            let endPoint = CGPoint(
                x: keypoints[endIdx][0] * scaleX + offsetX,
                y: keypoints[endIdx][1] * scaleY + offsetY
            )
            
            // Gradient line
            let path = Path { path in
                path.move(to: startPoint)
                path.addLine(to: endPoint)
            }
            
            context.stroke(
                path,
                with: .color(color),
                lineWidth: 2 // Line width as per style guide
            )
        }
        
        // Enhanced keypoints with glow effect - filtered by exercise type
        for (index, keypoint) in keypoints.enumerated() {
            guard index < confidence.count && confidence[index] > 0.3 else { continue }
            
            // Filter keypoints based on exercise type
            let shouldShowKeypoint: Bool
            switch exerciseType {
            case .shoulderShrugs, .shoulderSqueezes:
                // Only show face (0-4), shoulders (5-6), and elbows (7-8) for shoulder exercises
                shouldShowKeypoint = index <= 8
            case .neckRotations, .sideLegRaises:
                // Show all keypoints for other exercises
                shouldShowKeypoint = true
            }
            
            guard shouldShowKeypoint else { continue }
            
            let point = CGPoint(
                x: keypoint[0] * scaleX + offsetX,
                y: keypoint[1] * scaleY + offsetY
            )
            
            // Main joint dot - clean style guide appearance
            let rect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12) // 6px radius
            context.fill(Path(ellipseIn: rect), with: .color(Color.white))
        }
    }
}