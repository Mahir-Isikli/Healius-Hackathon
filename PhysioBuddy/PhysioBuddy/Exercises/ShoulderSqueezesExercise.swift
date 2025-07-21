import Foundation

class ShoulderSqueezesExercise: BaseExerciseImpl, BaseExercise {
    // MARK: - Properties
    
    var name: String { "Shoulder Squeezes" }
    var description: String { "Squeeze your shoulder blades together and hold, then release" }
    var requiredKeypoints: [KeypointIndex] { [.leftShoulder, .rightShoulder] }
    
    // Exercise-specific state
    private var baselineDistance: Double?
    private var inSqueeze: Bool = false
    private var lastDistance: Double?
    
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
                feedbackMessages: ["Cannot see shoulders clearly"],
                repCount: repCount,
                isProperPosition: false,
                confidence: 0.0,
                exerciseSpecificData: [:]
            )
        }
        
        // Get shoulder positions
        guard keypoints.count > KeypointIndex.rightShoulder.rawValue else {
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
        
        let leftShoulder = keypoints[KeypointIndex.leftShoulder.rawValue]
        let rightShoulder = keypoints[KeypointIndex.rightShoulder.rawValue]
        
        // Calculate shoulder distance (horizontal distance)
        let shoulderDistance = abs(leftShoulder[0] - rightShoulder[0])
        
        var feedbackMessages: [String] = []
        var formScore: Double = 70 // Base score
        
        switch currentPhase {
        case .active:
            // Establish baseline on first frame
            if baselineDistance == nil {
                baselineDistance = shoulderDistance
                print("💪 Baseline shoulder distance: \(shoulderDistance)")
            }
            if let baseline = baselineDistance {
                // Calculate squeeze percentage
                let squeezeAmount = baseline - shoulderDistance
                let squeezePercent = (squeezeAmount / baseline) * 100
                
                // Debug logging
                if Int(elapsedTime) % 2 == 0 { // Log every 2 seconds
                    print("💪 Squeeze debug - baseline: \(baseline), current: \(shoulderDistance), amount: \(squeezeAmount), percent: \(squeezePercent)%")
                }
                
                // Detect squeeze (>10% reduction in distance) - more sensitive
                if squeezePercent > 10 {
                    if !inSqueeze {
                        inSqueeze = true
                        formScore = 90
                        print("✅ Squeeze detected! Amount: \(squeezePercent)%")
                    } else {
                        formScore = 85
                    }
                    feedbackMessages.append("Hold (1s)")
                } else {
                    if inSqueeze {
                        // Just released
                        repCount += 1
                        inSqueeze = false
                        print("✅ Rep \(repCount) completed!")
                    }
                    feedbackMessages.append("Squeeze")
                    formScore = 60
                }
            }
            
        case .cooldown:
            feedbackMessages.append("Great work! You completed \(repCount) shoulder squeezes")
            formScore = 85
            
        default:
            feedbackMessages.append("Exercise not started")
        }
        
        // Calculate minimum confidence for required keypoints
        let minConfidence = requiredKeypoints.compactMap { idx in
            idx.rawValue < confidence.count ? confidence[idx.rawValue] : nil
        }.min() ?? 0.0
        
        return ExerciseAnalysisResult(
            exerciseName: name,
            phase: currentPhase,
            formScore: formScore,
            feedbackMessages: feedbackMessages,
            repCount: repCount,
            isProperPosition: true,
            confidence: minConfidence * 100,
            exerciseSpecificData: [
                "shoulder_distance": shoulderDistance,
                "baseline_distance": baselineDistance ?? 0,
                "in_squeeze": inSqueeze
            ]
        )
    }
}