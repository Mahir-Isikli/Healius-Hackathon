import Foundation

class ShoulderShrugsExercise: BaseExerciseImpl, BaseExercise {
    // MARK: - Properties
    
    var name: String { "Shoulder Shrugs" }
    var description: String { "Lift your shoulders up towards your ears, hold, then release" }
    var requiredKeypoints: [KeypointIndex] { [.leftShoulder, .rightShoulder, .leftEar, .rightEar] }
    
    // Exercise-specific state
    private var baselineShoulderY: Double?
    private var inShrug: Bool = false
    private let shrugThreshold: Double = 0.08 // 8% of ear-shoulder distance - more sensitive
    
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
                feedbackMessages: ["Cannot see shoulders and ears clearly"],
                repCount: repCount,
                isProperPosition: false,
                confidence: 0.0,
                exerciseSpecificData: [:]
            )
        }
        
        // Get keypoint positions
        guard keypoints.count > KeypointIndex.rightEar.rawValue else {
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
        let leftEar = keypoints[KeypointIndex.leftEar.rawValue]
        let rightEar = keypoints[KeypointIndex.rightEar.rawValue]
        
        // Calculate average shoulder Y position (lower Y = higher position in image coordinates)
        let avgShoulderY = (leftShoulder[1] + rightShoulder[1]) / 2
        let avgEarY = (leftEar[1] + rightEar[1]) / 2
        
        // Calculate the baseline distance between ears and shoulders
        let earShoulderDistance = abs(avgEarY - avgShoulderY)
        
        var feedbackMessages: [String] = []
        var formScore: Double = 70 // Base score
        
        switch currentPhase {
        case .active:
            // Establish baseline on first frame
            if baselineShoulderY == nil {
                baselineShoulderY = avgShoulderY
                print("🤷 Baseline established at Y: \(avgShoulderY)")
            }
            if let baseline = baselineShoulderY {
                // Calculate shrug amount (shoulders moving up means Y decreases)
                let shrugAmount = baseline - avgShoulderY
                let shrugPercent = shrugAmount / earShoulderDistance
                
                // Debug logging
                if Int(elapsedTime) % 2 == 0 { // Log every 2 seconds
                    print("🤷 Shrug debug - baseline: \(baseline), current: \(avgShoulderY), amount: \(shrugAmount), percent: \(shrugPercent * 100)%")
                }
                
                // Detect shrug (shoulders lifted by >8% of ear-shoulder distance)
                if shrugPercent > shrugThreshold {
                    if !inShrug {
                        inShrug = true
                        formScore = 90
                        print("✅ Shrug detected! Amount: \(shrugPercent * 100)%")
                    } else {
                        formScore = 85
                    }
                    feedbackMessages.append("Hold (1s)")
                } else {
                    if inShrug {
                        // Just released
                        repCount += 1
                        inShrug = false
                        print("✅ Rep \(repCount) completed!")
                    }
                    feedbackMessages.append("Lift")
                    formScore = 60
                }
            }
            
        case .cooldown:
            feedbackMessages.append("Great work! You completed \(repCount) shoulder shrugs")
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
                "shoulder_y": avgShoulderY,
                "baseline_shoulder_y": baselineShoulderY ?? 0,
                "in_shrug": inShrug,
                "ear_shoulder_distance": earShoulderDistance
            ]
        )
    }
}