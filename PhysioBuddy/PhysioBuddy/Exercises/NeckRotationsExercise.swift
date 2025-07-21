import Foundation

class NeckRotationsExercise: BaseExerciseImpl, BaseExercise {
    // MARK: - Properties
    
    var name: String { "Neck Rotations" }
    var description: String { "Slowly rotate your head left and right" }
    var requiredKeypoints: [KeypointIndex] { [.nose, .leftShoulder, .rightShoulder] }
    
    // Exercise-specific state
    private var shoulderMidpointX: Double?
    private var lastNoseX: Double?
    private var rotationDirection: String? // "left" or "right"
    private var leftRotations: Int = 0
    private var rightRotations: Int = 0
    private let rotationThreshold: Double = 30 // pixels
    
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
                feedbackMessages: ["Cannot see face and shoulders clearly"],
                repCount: leftRotations + rightRotations,
                isProperPosition: false,
                confidence: 0.0,
                exerciseSpecificData: [:]
            )
        }
        
        // Get keypoint positions
        guard keypoints.count > KeypointIndex.rightShoulder.rawValue else {
            return ExerciseAnalysisResult(
                exerciseName: name,
                phase: currentPhase,
                formScore: 0.0,
                feedbackMessages: ["Invalid keypoint data"],
                repCount: leftRotations + rightRotations,
                isProperPosition: false,
                confidence: 0.0,
                exerciseSpecificData: [:]
            )
        }
        
        let nose = keypoints[KeypointIndex.nose.rawValue]
        let leftShoulder = keypoints[KeypointIndex.leftShoulder.rawValue]
        let rightShoulder = keypoints[KeypointIndex.rightShoulder.rawValue]
        
        // Calculate shoulder midpoint
        let currentShoulderMidpointX = (leftShoulder[0] + rightShoulder[0]) / 2
        
        // Track nose position relative to shoulders
        let noseOffset = nose[0] - currentShoulderMidpointX
        
        var feedbackMessages: [String] = []
        var formScore: Double = 70 // Base score
        
        switch currentPhase {
        case .active:
            // Establish shoulder midpoint baseline on first frame
            if shoulderMidpointX == nil {
                shoulderMidpointX = currentShoulderMidpointX
                print("🤸 Shoulder midpoint baseline: \(currentShoulderMidpointX)")
            }
            // First half: focus on left rotations
            if elapsedTime < 180 { // First 3 minutes (including setup)
                if noseOffset < -rotationThreshold {
                    if rotationDirection != "left" {
                        leftRotations += 1
                        rotationDirection = "left"
                        feedbackMessages.append("Left rotation \(leftRotations)")
                        formScore = 90
                    } else {
                        feedbackMessages.append("Good left rotation, now slowly return to center")
                        formScore = 85
                    }
                } else if noseOffset > rotationThreshold {
                    feedbackMessages.append("Focus on rotating to your left for now")
                    formScore = 60
                } else {
                    rotationDirection = nil
                    feedbackMessages.append("Now rotate your head to the left")
                    formScore = 70
                }
            } else {
                // Second half: focus on right rotations
                if noseOffset > rotationThreshold {
                    if rotationDirection != "right" {
                        rightRotations += 1
                        rotationDirection = "right"
                        feedbackMessages.append("Right rotation \(rightRotations)")
                        formScore = 90
                    } else {
                        feedbackMessages.append("Good right rotation, now slowly return to center")
                        formScore = 85
                    }
                } else if noseOffset < -rotationThreshold {
                    feedbackMessages.append("Focus on rotating to your right for now")
                    formScore = 60
                } else {
                    rotationDirection = nil
                    feedbackMessages.append("Now rotate your head to the right")
                    formScore = 70
                }
            }
            
        case .cooldown:
            let totalRotations = leftRotations + rightRotations
            feedbackMessages.append("Excellent! \(leftRotations) left, \(rightRotations) right rotations")
            formScore = 85
            
        default:
            feedbackMessages.append("Exercise not started")
        }
        
        repCount = leftRotations + rightRotations
        
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
                "nose_offset": noseOffset,
                "left_rotations": leftRotations,
                "right_rotations": rightRotations,
                "rotation_direction": rotationDirection ?? ""
            ]
        )
    }
}