import Foundation
import AVFoundation
import Combine
import UIKit

// ConnectionState is defined in AppState.swift - using that definition

// KeypointData and ExerciseAnalysisData are defined in PoseRTC.swift - using those definitions

// ExerciseType is defined in PoseRTC.swift - using that definition

final class WebSocketPoseDetector: NSObject, ObservableObject {
    // Published properties - same as PoseRTC for compatibility
    @Published var latestKeypointData: KeypointData?
    @Published var currentRepCount: Int = 0
    @Published var currentFormScore: Double = 0
    @Published var currentPhase: String = "not_started"
    @Published var feedbackMessages: [String] = []
    @Published var connectionState: ConnectionState = .disconnected
    
    var selectedExercise: ExerciseType = .shoulderSqueezes
    var serverURL: String = "wss://730f52286f27.ngrok-free.app"
    
    // WebSocket and camera management
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var frameCount = 0
    private var isCapturing = false
    
    // Camera preview layer for UI
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    // Timers for frame sending
    private var frameTimer: Timer?
    
    override init() {
        super.init()
        print("🔗 WebSocketPoseDetector initializing")
        
        setupURLSession()
    }
    
    deinit {
        print("🧹 WebSocketPoseDetector deinitializing")
        stopSession()
    }
    
    // MARK: - Setup
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - Camera Setup
    
    func startCamera() {
        print("📱 Starting camera capture...")
        
        guard !isCapturing else {
            print("📱 Camera already capturing")
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupCaptureSession()
        }
    }
    
    private func setupCaptureSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("❌ Failed to get front camera device")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            captureSession = AVCaptureSession()
            
            // Configure session for lower resolution to improve performance
            captureSession?.sessionPreset = .vga640x480
            
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }
            
            // Setup video output
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frame.processing"))
            videoOutput?.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            
            if captureSession?.canAddOutput(videoOutput!) == true {
                captureSession?.addOutput(videoOutput!)
            }
            
            // Setup preview layer for UI
            DispatchQueue.main.async {
                self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession!)
                self.previewLayer?.videoGravity = .resizeAspectFill
            }
            
            // Start session on background thread (as recommended by Apple)
            self.captureSession?.startRunning()
            
            // Update UI state on main thread
            DispatchQueue.main.async {
                self.isCapturing = true
                print("📱 Camera capture session started")
            }
            
        } catch {
            print("❌ Failed to setup camera: \(error)")
        }
    }
    
    // MARK: - WebSocket Connection
    
    func startSession() {
        print("🚀 Starting WebSocket session with exercise: \(selectedExercise.rawValue)")
        
        connectWebSocket()
        startCamera()
    }
    
    func stopSession() {
        print("⏹️ Stopping WebSocket session")
        
        // Stop camera
        captureSession?.stopRunning()
        isCapturing = false
        
        // Stop frame timer
        frameTimer?.invalidate()
        frameTimer = nil
        
        // Close WebSocket
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        
        // Reset state
        DispatchQueue.main.async {
            self.connectionState = .disconnected
            self.currentRepCount = 0
            self.currentFormScore = 0
            self.currentPhase = "not_started"
            self.feedbackMessages = []
            self.latestKeypointData = nil
        }
    }
    
    private func connectWebSocket() {
        guard let url = URL(string: "\(serverURL)/pose-analysis") else {
            print("❌ Invalid WebSocket URL")
            return
        }
        
        print("🔗 Connecting to WebSocket: \(url)")
        
        DispatchQueue.main.async {
            self.connectionState = .connecting
        }
        
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()
        
        // Start listening for messages
        receiveMessage()
        
        // Send exercise type
        sendExerciseType()
    }
    
    private func sendExerciseType() {
        let exerciseMessage = [
            "type": "set_exercise",
            "exercise_type": selectedExercise.rawValue
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exerciseMessage)
            let message = URLSessionWebSocketTask.Message.string(String(data: jsonData, encoding: .utf8)!)
            webSocket?.send(message) { error in
                if let error = error {
                    print("❌ Failed to send exercise type: \(error)")
                } else {
                    print("📤 Sent exercise type: \(self.selectedExercise.rawValue)")
                }
            }
        } catch {
            print("❌ Failed to encode exercise message: \(error)")
        }
    }
    
    // MARK: - Message Handling
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleTextMessage(text)
                case .data(let data):
                    print("📡 Received binary data: \(data.count) bytes")
                @unknown default:
                    break
                }
                
                // Continue listening
                self?.receiveMessage()
                
            case .failure(let error):
                print("❌ WebSocket receive error: \(error)")
                DispatchQueue.main.async {
                    self?.connectionState = .failed
                }
            }
        }
    }
    
    private func handleTextMessage(_ text: String) {
        print("📡 Received message: \(text.prefix(100))...")
        
        do {
            guard let data = text.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Failed to parse JSON")
                return
            }
            
            let messageType = json["type"] as? String
            
            switch messageType {
            case "keypoints":
                parseKeypointData(json)
            case "exercise_set":
                print("✅ Exercise type set successfully")
                DispatchQueue.main.async {
                    self.connectionState = .connected
                }
            case "error":
                let errorMessage = json["message"] as? String ?? "Unknown error"
                print("❌ Server error: \(errorMessage)")
            default:
                print("⚠️ Unknown message type: \(messageType ?? "nil")")
            }
            
        } catch {
            print("❌ Error parsing message: \(error)")
        }
    }
    
    private func parseKeypointData(_ json: [String: Any]) {
        guard let keypointsArray = json["keypoints"] as? [[Double]],
              let confidenceArray = json["confidence"] as? [Double],
              let timestamp = json["timestamp"] as? Double else {
            print("❌ Invalid keypoint data format")
            return
        }
        
        // Parse exercise analysis data
        var exerciseAnalysis: ExerciseAnalysisData?
        if let analysisData = json["exercise_analysis"] as? [String: Any] {
            exerciseAnalysis = ExerciseAnalysisData(
                exerciseName: analysisData["exercise_name"] as? String,
                phase: analysisData["phase"] as? String ?? "not_started",
                formScore: analysisData["form_score"] as? Double ?? 0,
                repCount: analysisData["rep_count"] as? Int ?? 0,
                feedbackMessages: analysisData["feedback_messages"] as? [String] ?? []
            )
        }
        
        let keypointData = KeypointData(
            keypoints: keypointsArray,
            confidence: confidenceArray,
            timestamp: timestamp,
            exerciseAnalysis: exerciseAnalysis
        )
        
        // Update published properties on main thread
        DispatchQueue.main.async {
            self.latestKeypointData = keypointData
            
            if let analysis = exerciseAnalysis {
                self.currentRepCount = analysis.repCount
                self.currentFormScore = analysis.formScore
                self.currentPhase = analysis.phase
                self.feedbackMessages = analysis.feedbackMessages
                
                print("📊 Updated exercise stats: Reps=\(analysis.repCount), Form=\(analysis.formScore)%, Phase=\(analysis.phase)")
            }
            
            // Update connection state if needed
            if self.connectionState != .connected {
                self.connectionState = .connected
            }
        }
    }
    
    // MARK: - Frame Sending
    
    private func sendFrame(_ imageData: Data) {
        guard connectionState == .connected else { return }
        
        let message = URLSessionWebSocketTask.Message.data(imageData)
        webSocket?.send(message) { error in
            if let error = error {
                print("❌ Failed to send frame: \(error)")
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension WebSocketPoseDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        
        // Only send every 10th frame to reduce load (approximately 3fps for better performance)
        guard frameCount % 10 == 0 else { return }
        
        // Convert sample buffer to JPEG
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        // Compress and send (lower quality for better performance)
        if let jpegData = uiImage.jpegData(compressionQuality: 0.4) {
            sendFrame(jpegData)
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketPoseDetector: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket connected")
        DispatchQueue.main.async {
            self.connectionState = .connected
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("📡 WebSocket closed with code: \(closeCode)")
        DispatchQueue.main.async {
            self.connectionState = .disconnected
        }
    }
}