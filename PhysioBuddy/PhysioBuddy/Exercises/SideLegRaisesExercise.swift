import Foundation

class SideLegRaisesExercise: BaseExerciseImpl, BaseExercise {
    // MARK: - Properties
    
    var name: String { "Side Leg Raises" }
    var description: String { "Lift your leg to the side and return to starting position" }
    var requiredKeypoints: [KeypointIndex] { [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle] }
    
    // Exercise-specific state
    private var baselinePosition: [Double]?
    private var lastHipWidth: Double? // Track hip width for adaptive threshold
    private var inRaise: Bool = false
    private var activeLeg: String = "right" // Start with right leg
    private var lastValidRaise: TimeInterval = 0
    private let minTimeBetweenReps: Double = 1.0 // minimum 1 second between reps
    
    // Adaptive thresholds based on body proportions
    private let relativeThresholdFactor: Double = 0.4 // 40% of hip width for threshold
    private let minThreshold: Double = 20.0 // minimum absolute threshold
    private let maxThreshold: Double = 80.0 // maximum absolute threshold
    
    // MARK: - Analysis
    
    func analyze(keypoints: [[Double]], confidence: [Double], elapsedTime: TimeInterval) -> ExerciseAnalysisResult {
        // Update phase
        let currentPhase = updatePhase(elapsedTime: elapsedTime)
        
        // Check confidence
        guard checkConfidence(confidence: confidence, requiredIndices: requiredKeypoints) else {
            return ExerciseAnalysisResult(
                exerciseName: name,
                phase: currentPhase,
                formScore: 0.0,
                feedbackMessages: ["Cannot see hips and legs clearly"],
                repCount: repCount,
                isProperPosition: false,
                confidence: 0.0,
                exerciseSpecificData: [:]
            )
        }
        
        // Get keypoint positions
        guard keypoints.count > KeypointIndex.rightAnkle.rawValue else {
            return ExerciseAnalysisResult(
                exerciseName: name,
                phase: currentPhase,
                formScore: 0.0,
                feedbackMessages: ["Invalid keypoint data"],
                repCount: repCount,
                isProperPosition: false,
                confidence: 0.0,
                exerciseSpecificData: [:]
            )
        }
        
        let leftHip = keypoints[KeypointIndex.leftHip.rawValue]
        let rightHip = keypoints[KeypointIndex.rightHip.rawValue]
        let leftKnee = keypoints[KeypointIndex.leftKnee.rawValue]
        let rightKnee = keypoints[KeypointIndex.rightKnee.rawValue]
        let leftAnkle = keypoints[KeypointIndex.leftAnkle.rawValue]
        let rightAnkle = keypoints[KeypointIndex.rightAnkle.rawValue]
        
        // Calculate current hip width for adaptive threshold
        let currentHipWidth = sqrt(pow(rightHip[0] - leftHip[0], 2) + pow(rightHip[1] - leftHip[1], 2))
        
        // Get current leg position (ankle position as main indicator)
        let currentPosition: [Double]
        if activeLeg == "right" {
            currentPosition = rightAnkle
        } else {
            currentPosition = leftAnkle
        }
        
        var feedbackMessages: [String] = []
        var formScore: Double = 70 // Base score
        
        switch currentPhase {
        case .active:
            // Check if coordinate system changed by comparing hip width
            let coordinateSystemChanged: Bool
            if let lastWidth = lastHipWidth {
                let widthChange = abs(currentHipWidth - lastWidth) / lastWidth
                coordinateSystemChanged = widthChange > 0.3 // 30% change indicates coordinate system shift
            } else {
                coordinateSystemChanged = true // First frame
            }
            
            // Reset baseline if coordinate system changed or first frame
            if coordinateSystemChanged || baselinePosition == nil {
                baselinePosition = currentPosition
                lastHipWidth = currentHipWidth
                inRaise = false // Reset raise state on coordinate change
                print("🦵 Baseline reset - position: [\(currentPosition[0]), \(currentPosition[1])], hip width: \(currentHipWidth)")
            }
            
            if let baseline = baselinePosition {
                // Calculate adaptive threshold based on hip width
                let adaptiveThreshold = max(minThreshold, min(maxThreshold, currentHipWidth * relativeThresholdFactor))
                
                // Calculate lateral distance (mainly x-axis movement for side raises)
                let lateralDistance = abs(currentPosition[0] - baseline[0])
                let verticalDistance = abs(currentPosition[1] - baseline[1])
                
                // Focus on lateral movement but consider some vertical
                let movementDistance = lateralDistance * 0.8 + verticalDistance * 0.2
                
                // Debug logging (reduced frequency to avoid spam)
                if Int(elapsedTime * 2) % 5 == 0 { // Every 2.5 seconds
                    print("🦵 Leg raise debug - baseline: [\(baseline[0]), \(baseline[1])], current: [\(currentPosition[0]), \(currentPosition[1])], lateral: \(lateralDistance), movement: \(movementDistance), leg: \(activeLeg)")
                    print("🦵 Movement: \(movementDistance) pixels, adaptive threshold: \(adaptiveThreshold) (hip width: \(currentHipWidth))")
                }
                
                // Detect leg raise based on adaptive movement distance
                if movementDistance > adaptiveThreshold {
                    if !inRaise {
                        inRaise = true
                        lastValidRaise = elapsedTime
                        formScore = 90
                        print("✅ Leg raise detected! Movement: \(movementDistance) pixels (threshold: \(adaptiveThreshold))")
                    } else {
                        formScore = 85
                    }
                    feedbackMessages.append("Hold (1s)")
                } else {
                    if inRaise && (elapsedTime - lastValidRaise) >= minTimeBetweenReps {
                        // Just returned to starting position and enough time has passed
                        repCount += 1
                        inRaise = false
                        print("✅ Rep \(repCount) completed!")
                    }
                    feedbackMessages.append("Lift")
                    formScore = 60
                }
            }
            
            // Switch legs halfway through
            if elapsedTime > 180 && activeLeg == "right" {
                activeLeg = "left"
                baselinePosition = nil // Reset baseline for left leg
                lastHipWidth = nil // Reset hip width tracking
                inRaise = false
                feedbackMessages.append("Switch to left leg raises")
                print("🔄 Switching to left leg")
            }
            
        case .cooldown:
            feedbackMessages.append("Great work! You completed \(repCount) side leg raises")
            formScore = 85
            
        default:
            feedbackMessages.append("Exercise not started")
        }
        
        // Calculate minimum confidence for required keypoints
        let minConfidence = requiredKeypoints.compactMap { idx in
            idx.rawValue < confidence.count ? confidence[idx.rawValue] : nil
        }.min() ?? 0.0
        
        // Calculate adaptive threshold for debugging
        let currentAdaptiveThreshold = max(minThreshold, min(maxThreshold, currentHipWidth * relativeThresholdFactor))
        
        return ExerciseAnalysisResult(
            exerciseName: name,
            phase: currentPhase,
            formScore: formScore,
            feedbackMessages: feedbackMessages,
            repCount: repCount,
            isProperPosition: true,
            confidence: minConfidence * 100,
            exerciseSpecificData: [
                "current_position": currentPosition,
                "baseline_position": baselinePosition ?? [0, 0],
                "in_raise": inRaise,
                "active_leg": activeLeg,
                "hip_width": currentHipWidth,
                "adaptive_threshold": currentAdaptiveThreshold,
                "coordinate_system_stable": lastHipWidth != nil
            ]
        )
    }
    
}