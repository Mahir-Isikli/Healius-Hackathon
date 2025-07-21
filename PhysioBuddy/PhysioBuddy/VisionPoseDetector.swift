import Foundation
import AVFoundation
import Vision
import SwiftUI
import Combine

final class VisionPoseDetector: NSObject, ObservableObject {
    // Published properties - same interface as PoseRTC for easy migration
    @Published var latestKeypointData: KeypointData?
    @Published var currentRepCount: Int = 0
    @Published var currentFormScore: Double = 0
    @Published var currentPhase: String = "not_started"
    @Published var feedbackMessages: [String] = []
    @Published var cameraFrameSize: CGSize = CGSize(width: 640, height: 480)
    
    // Camera and Vision
    let captureSession = AVCaptureSession() // Made public for CameraPreviewView
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "VisionPoseDetector.videoDataOutputQueue")
    
    // Pose detection
    private lazy var poseRequest: VNDetectHumanBodyPoseRequest = {
        let request = VNDetectHumanBodyPoseRequest()
        request.revision = VNDetectHumanBodyPoseRequestRevision1
        return request
    }()
    
    // Exercise configuration
    var selectedExercise: ExerciseType = .shoulderSqueezes
    
    // Session state
    private var isSessionActive = false
    private var frameCount = 0
    
    override init() {
        super.init()
        setupCamera()
    }
    
    // MARK: - Camera Setup
    
    private func setupCamera() {
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("❌ Failed to get front camera device")
            return
        }
        
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            captureSession.beginConfiguration()
            
            // Add video input
            if captureSession.canAddInput(videoDeviceInput) {
                captureSession.addInput(videoDeviceInput)
            } else {
                print("❌ Cannot add video input")
                captureSession.commitConfiguration()
                return
            }
            
            // Configure video output
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            if captureSession.canAddOutput(videoDataOutput) {
                captureSession.addOutput(videoDataOutput)
            } else {
                print("❌ Cannot add video output")
                captureSession.commitConfiguration()
                return
            }
            
            // Configure session preset for better performance
            if captureSession.canSetSessionPreset(.vga640x480) {
                captureSession.sessionPreset = .vga640x480
                print("📹 Camera preset set to VGA 640x480")
            } else if captureSession.canSetSessionPreset(.medium) {
                captureSession.sessionPreset = .medium
                print("📹 Camera preset set to medium")
            } else {
                print("📹 Using default camera preset")
            }
            
            captureSession.commitConfiguration()
            
            print("✅ Camera setup completed successfully")
            
        } catch {
            print("❌ Error setting up camera: \(error)")
        }
    }
    
    // MARK: - Session Management
    
    func startSession() {
        print("🚀 Starting Vision pose detection session")
        isSessionActive = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            print("📹 Capture session started")
        }
    }
    
    func stopSession() {
        print("⏹️ Stopping Vision pose detection session")
        isSessionActive = false
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
            print("📹 Capture session stopped")
        }
        
        // Reset published properties
        DispatchQueue.main.async {
            self.currentRepCount = 0
            self.currentFormScore = 0
            self.currentPhase = "not_started"
            self.feedbackMessages = []
            self.latestKeypointData = nil
        }
    }
    
    // MARK: - Pose Detection
    
    private func performPoseDetection(on pixelBuffer: CVPixelBuffer) {
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        do {
            try requestHandler.perform([poseRequest])
            
            guard let observation = poseRequest.results?.first else {
                // No pose detected
                return
            }
            
            let keypoints = extractKeypointsFromObservation(observation, pixelBuffer: pixelBuffer)
            let timestamp = Date().timeIntervalSince1970
            
            // Create keypoint data
            let keypointData = KeypointData(
                keypoints: keypoints.coordinates,
                confidence: keypoints.confidence,
                timestamp: timestamp,
                exerciseAnalysis: nil // TODO: Implement exercise analysis
            )
            
            // Update on main thread
            DispatchQueue.main.async {
                self.latestKeypointData = keypointData
                
                // TODO: Add exercise analysis logic here
                // For now, simulate some data
                if self.isSessionActive {
                    self.simulateExerciseAnalysis()
                }
            }
            
        } catch {
            print("❌ Error performing pose detection: \(error)")
        }
    }
    
    // MARK: - Keypoint Extraction and Mapping
    
    private func extractKeypointsFromObservation(_ observation: VNHumanBodyPoseObservation, pixelBuffer: CVPixelBuffer) -> (coordinates: [[Double]], confidence: [Double]) {
        
        let imageWidth = Double(CVPixelBufferGetWidth(pixelBuffer))
        let imageHeight = Double(CVPixelBufferGetHeight(pixelBuffer))
        
        // Update camera frame size and log buffer dimensions every few frames
        let currentFrameSize = CGSize(width: imageWidth, height: imageHeight)
        if frameCount % 60 == 0 {
            print("📐 Buffer dimensions: \(Int(imageWidth)) x \(Int(imageHeight))")
            DispatchQueue.main.async {
                self.cameraFrameSize = currentFrameSize
            }
        }
        
        // Define the mapping from Vision joints to COCO format indices
        let visionToCOCOMapping: [(VNHumanBodyPoseObservation.JointName, Int)] = [
            (.nose, 0),
            (.leftEye, 1),
            (.rightEye, 2),
            (.leftEar, 3),
            (.rightEar, 4),
            (.leftShoulder, 5),
            (.rightShoulder, 6),
            (.leftElbow, 7),
            (.rightElbow, 8),
            (.leftWrist, 9),
            (.rightWrist, 10),
            (.leftHip, 11),
            (.rightHip, 12),
            (.leftKnee, 13),
            (.rightKnee, 14),
            (.leftAnkle, 15),
            (.rightAnkle, 16)
        ]
        
        var coordinates = Array(repeating: [0.0, 0.0], count: 17)
        var confidence = Array(repeating: 0.0, count: 17)
        
        do {
            let recognizedPoints = try observation.recognizedPoints(.all)
            var detectedJointsCount = 0
            var detectedJointNames: [String] = []
            
            if frameCount % 60 == 0 {
                print("🔍 Vision detected \(recognizedPoints.count) total points")
            }
            
            for (visionJoint, cocoIndex) in visionToCOCOMapping {
                if let point = recognizedPoints[visionJoint] {
                    // Only include points with reasonable confidence (lowered for debugging)
                    if point.confidence > 0.1 {
                        // Vision coordinates are normalized (0-1), convert to pixel coordinates
                        // Note: Vision Y is flipped (0 is bottom), so we need to flip it
                        let x = point.location.x * imageWidth
                        let y = (1.0 - point.location.y) * imageHeight
                        
                        coordinates[cocoIndex] = [x, y]
                        confidence[cocoIndex] = Double(point.confidence)
                        detectedJointsCount += 1
                        detectedJointNames.append("\(visionJoint)")
                        
                        // Log key joints for debugging
                        if frameCount % 60 == 0 && [0, 5, 6, 11, 12].contains(cocoIndex) { // nose, shoulders, hips
                            print("🎯 \(visionJoint): (\(Int(x)), \(Int(y))) conf: \(String(format: "%.2f", point.confidence))")
                        }
                    } else {
                        // Set low confidence joints to [0,0] to ensure they're not displayed
                        coordinates[cocoIndex] = [0.0, 0.0]
                        confidence[cocoIndex] = 0.0
                    }
                } else {
                    // Joint not detected
                    coordinates[cocoIndex] = [0.0, 0.0]
                    confidence[cocoIndex] = 0.0
                }
            }
            
            if frameCount % 60 == 0 {
                print("📊 Vision: \(detectedJointsCount)/17 joints detected with conf > 0.1")
                print("🔗 Detected joints: \(detectedJointNames.joined(separator: ", "))")
            }
            
        } catch {
            print("❌ Error extracting recognized points: \(error)")
        }
        
        return (coordinates, confidence)
    }
    
    // MARK: - Exercise Analysis (Placeholder)
    
    private func simulateExerciseAnalysis() {
        // TODO: Port exercise analysis logic from backend
        // For now, simulate some realistic values
        
        let phases = ["setup", "active", "rest"]
        let currentTime = Date().timeIntervalSince1970
        let phaseIndex = Int(currentTime / 3) % phases.count
        
        currentPhase = phases[phaseIndex]
        currentFormScore = Double.random(in: 70...95)
        
        // Simulate rep counting
        if currentPhase == "active" && Int(currentTime) % 5 == 0 {
            currentRepCount += 1
        }
        
        // Simulate feedback
        let feedbackOptions = [
            "Good form! Keep it up",
            "Squeeze your shoulders",
            "Hold the position",
            "Focus on control",
            "Excellent posture"
        ]
        
        if currentPhase == "active" {
            feedbackMessages = [feedbackOptions.randomElement() ?? ""]
        } else {
            feedbackMessages = []
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension VisionPoseDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard isSessionActive else { return }
        
        frameCount += 1
        
        // Process every 2nd frame for performance (15fps effective rate)
        guard frameCount % 2 == 0 else { return }
        
        // Log every 30th processed frame
        if frameCount % 60 == 0 {
            print("📹 Processed \(frameCount/2) frames for pose detection")
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("❌ Failed to get pixel buffer from sample buffer")
            return
        }
        
        performPoseDetection(on: pixelBuffer)
    }
}