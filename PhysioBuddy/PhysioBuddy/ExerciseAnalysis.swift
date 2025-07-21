import Foundation

// MARK: - Enums and Data Structures

enum ExercisePhase: String {
    case notStarted = "not_started"
    case active = "active"
    case cooldown = "cooldown"
    case completed = "completed"
}

struct ExerciseAnalysisResult {
    let exerciseName: String
    let phase: ExercisePhase
    let formScore: Double // 0-100 percentage
    let feedbackMessages: [String]
    let repCount: Int
    let isProperPosition: Bool
    let confidence: Double
    let exerciseSpecificData: [String: Any]
}

// MARK: - Keypoint Indices (matching COCO format)

enum KeypointIndex: Int {
    case nose = 0
    case leftEye = 1
    case rightEye = 2
    case leftEar = 3
    case rightEar = 4
    case leftShoulder = 5
    case rightShoulder = 6
    case leftElbow = 7
    case rightElbow = 8
    case leftWrist = 9
    case rightWrist = 10
    case leftHip = 11
    case rightHip = 12
    case leftKnee = 13
    case rightKnee = 14
    case leftAnkle = 15
    case rightAnkle = 16
}

// MARK: - Base Exercise Protocol

protocol BaseExercise: AnyObject {
    var name: String { get }
    var description: String { get }
    var requiredKeypoints: [KeypointIndex] { get }
    var repCount: Int { get set }
    var startTime: Date? { get set }
    var phase: ExercisePhase { get set }
    var confidenceThreshold: Double { get }
    var phaseDurations: [ExercisePhase: TimeInterval] { get }
    
    func analyze(keypoints: [[Double]], confidence: [Double], elapsedTime: TimeInterval) -> ExerciseAnalysisResult
}

// MARK: - Base Exercise Implementation

class BaseExerciseImpl {
    var repCount: Int = 0
    var startTime: Date?
    var phase: ExercisePhase = .notStarted
    let confidenceThreshold: Double = 0.6
    
    let phaseDurations: [ExercisePhase: TimeInterval] = [
        .active: 360,    // 6 minutes
        .cooldown: 10    // 10 seconds
    ]
    
    func updatePhase(elapsedTime: TimeInterval) -> ExercisePhase {
        if elapsedTime < 0 {
            self.phase = .notStarted
            return .notStarted
        }
        
        var cumulativeTime: TimeInterval = 0
        for (phase, duration) in [
            (ExercisePhase.active, phaseDurations[.active]!),
            (ExercisePhase.cooldown, phaseDurations[.cooldown]!)
        ] {
            cumulativeTime += duration
            if elapsedTime < cumulativeTime {
                self.phase = phase
                return phase
            }
        }
        
        self.phase = .completed
        return .completed
    }
    
    func calculateDistance(p1: (x: Double, y: Double), p2: (x: Double, y: Double)) -> Double {
        return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }
    
    func calculateAngle(p1: (x: Double, y: Double), p2: (x: Double, y: Double), p3: (x: Double, y: Double)) -> Double {
        // Calculate angle between three points (p2 is the vertex)
        let v1 = (x: p1.x - p2.x, y: p1.y - p2.y)
        let v2 = (x: p3.x - p2.x, y: p3.y - p2.y)
        
        let dotProduct = v1.x * v2.x + v1.y * v2.y
        
        let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)
        
        if mag1 == 0 || mag2 == 0 {
            return 0
        }
        
        let cosAngle = dotProduct / (mag1 * mag2)
        let clampedCosAngle = max(-1, min(1, cosAngle))
        let angleRad = acos(clampedCosAngle)
        
        return angleRad * 180 / .pi // Convert to degrees
    }
    
    func checkConfidence(confidence: [Double], requiredIndices: [KeypointIndex]) -> Bool {
        for idx in requiredIndices {
            if idx.rawValue < confidence.count && confidence[idx.rawValue] < confidenceThreshold {
                return false
            }
        }
        return true
    }
}

// MARK: - Exercise Manager

class ExerciseManager {
    static let shared = ExerciseManager()
    private var currentExercise: BaseExercise?
    private var exerciseStartTime: Date?
    
    private init() {}
    
    func startExercise(type: ExerciseType) {
        // Stop any existing exercise to ensure clean state
        stopExercise()
        
        exerciseStartTime = Date()
        
        switch type {
        case .shoulderSqueezes:
            currentExercise = ShoulderSqueezesExercise()
        case .shoulderShrugs:
            currentExercise = ShoulderShrugsExercise()
        case .sideLegRaises:
            currentExercise = SideLegRaisesExercise()
        case .neckRotations:
            currentExercise = NeckRotationsExercise()
        }
        
        currentExercise?.startTime = exerciseStartTime
        currentExercise?.phase = .notStarted
        currentExercise?.repCount = 0
    }
    
    func analyzeFrame(keypoints: [[Double]], confidence: [Double]) -> ExerciseAnalysisResult? {
        guard let exercise = currentExercise,
              let startTime = exerciseStartTime else {
            return nil
        }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        return exercise.analyze(keypoints: keypoints, confidence: confidence, elapsedTime: elapsedTime)
    }
    
    func stopExercise() {
        currentExercise = nil
        exerciseStartTime = nil
    }
    
    func resetExercise() {
        if let exercise = currentExercise {
            exercise.repCount = 0
            exercise.phase = .notStarted
            exerciseStartTime = Date()
            exercise.startTime = exerciseStartTime
        }
    }
}