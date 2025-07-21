import Foundation
import WebRTC
import AVFoundation
import Combine

// Keypoint data structure
struct KeypointData: Equatable {
    let keypoints: [[Double]]  // Array of [x, y] coordinates
    let confidence: [Double]   // Confidence scores for each keypoint
    let timestamp: Double
    let exerciseAnalysis: ExerciseAnalysisData?
    
    static func == (lhs: KeypointData, rhs: KeypointData) -> Bool {
        return lhs.timestamp == rhs.timestamp &&
               lhs.keypoints == rhs.keypoints &&
               lhs.confidence == rhs.confidence &&
               lhs.exerciseAnalysis == rhs.exerciseAnalysis
    }
}

struct ExerciseAnalysisData: Equatable {
    let exerciseName: String?
    let phase: String
    let formScore: Double
    let repCount: Int
    let feedbackMessages: [String]
}

enum ExerciseType: String, CaseIterable {
    case shoulderSqueezes = "shoulder_squeezes"
    case shoulderShrugs = "shoulder_shrugs"
    case neckRotations = "neck_rotations" 
    case sideLegRaises = "side_leg_raises"
    
    var displayName: String {
        switch self {
        case .shoulderSqueezes: return "Shoulder Squeezes"
        case .shoulderShrugs: return "Shoulder Shrugs"
        case .neckRotations: return "Neck Rotations"
        case .sideLegRaises: return "Side Leg Raises"
        }
    }
}

// Exercise groups for UI display
struct ExerciseGroup {
    let title: String
    let imageName: String
    let exercises: [ExerciseType]
    let description: String
}

extension ExerciseGroup {
    static let allGroups: [ExerciseGroup] = [
        ExerciseGroup(
            title: "Shoulder Exercises",
            imageName: "Shoulder_Shrug",
            exercises: [.shoulderSqueezes, .shoulderShrugs],
            description: "Strengthen and relax your shoulders"
        ),
        ExerciseGroup(
            title: "Hip Mobility",
            imageName: "Sideleg_raises",
            exercises: [.sideLegRaises],
            description: "Strengthen hip abductors and improve stability"
        )
    ]
}

final class PoseRTC: NSObject, ObservableObject, RTCVideoCapturerDelegate {
    private let factory = RTCPeerConnectionFactory()
    private var pc: RTCPeerConnection!
    private var capturer: RTCCameraVideoCapturer!
    private let videoSource: RTCVideoSource
    var onRemoteTrack: ((RTCVideoTrack) -> Void)?
    var selectedExercise: ExerciseType = .shoulderSqueezes
    var serverURL: String = Bundle.main.object(forInfoDictionaryKey: "SERVER_URL") as? String ?? ""
    
    // Connection management
    private var isConnecting = false
    private var shouldAutoReconnect = true
    private var reconnectionTimer: Timer?
    private var connectionCheckTimer: Timer?
    private var frameCount = 0
    
    // Data channel for receiving keypoint data
    private var dataChannel: RTCDataChannel?
    
    // Keypoint data handling
    @Published var latestKeypointData: KeypointData?
    @Published var currentRepCount: Int = 0
    @Published var currentFormScore: Double = 0
    @Published var currentPhase: String = "not_started"
    @Published var feedbackMessages: [String] = []
    @Published var connectionState: ConnectionState = .disconnected
    @Published var remoteTrack: RTCVideoTrack?

    override init() {
        RTCPeerConnectionFactory.initialize()
        videoSource = factory.videoSource()
        super.init()
        
        print("🏗️ PoseRTC initializing - creating new instance")
        
        // Configure WebRTC audio session to not disrupt other audio
        configureWebRTCAudioSession()

        createPeerConnection()

        capturer = RTCCameraVideoCapturer(delegate: self)
        let camTrack = factory.videoTrack(with: videoSource, trackId: "cam")
        pc.add(camTrack, streamIds: ["stream"])
        
        print("🏗️ PoseRTC initialization complete")
        
        // Auto-start camera and connection immediately
        print("🚀 Auto-starting camera and WebRTC connection...")
        startCamera()
        startBackgroundConnection()
    }
    
    deinit {
        print("🧹 PoseRTC deinitializing - this should NOT happen during active session!")
        // Temporarily removed automatic stopSession() to debug lifecycle issue
        shouldAutoReconnect = false
        reconnectionTimer?.invalidate()
        connectionCheckTimer?.invalidate()
    }
    
    // MARK: – Audio Configuration
    
    private func configureWebRTCAudioSession() {
        // Configure RTCAudioSession to not interfere with other audio
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.lockForConfiguration()
        defer { audioSession.unlockForConfiguration() }
        
        do {
            // Use ambient mode to allow mixing with other audio
            try audioSession.setCategory(.ambient, with: [.mixWithOthers])
            try audioSession.setMode(.default)
            try audioSession.setActive(false)
            
            // Disable WebRTC's automatic audio configuration
            audioSession.useManualAudio = true
            audioSession.isAudioEnabled = false
            
            print("🔊 WebRTC audio session configured to not disrupt other audio")
        } catch {
            print("⚠️ Failed to configure WebRTC audio session: \(error)")
        }
    }

    // MARK: – Camera

    func startCamera() {
        print("📱 Starting camera capture...")
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { 
            print("❌ Failed to get front camera device")
            return 
        }
        
        // Find a suitable high-quality format (at least 720p)
        let suitableFormats = device.formats.filter { format in
            let dimensions = format.formatDescription.dimensions
            // Accept formats with at least 720 pixels in one dimension
            return (dimensions.width >= 720 || dimensions.height >= 720)
        }.sorted { format1, format2 in
            let dims1 = format1.formatDescription.dimensions
            let dims2 = format2.formatDescription.dimensions
            // Prefer 1280x720 or 720x1280
            let area1 = Int(dims1.width) * Int(dims1.height)
            let area2 = Int(dims2.width) * Int(dims2.height)
            
            // Ideal area is 720*1280 = 921600
            let idealArea = 921600
            let diff1 = abs(area1 - idealArea)
            let diff2 = abs(area2 - idealArea)
            
            return diff1 < diff2
        }
        
        guard let format = suitableFormats.first ?? device.formats.last,
              let fpsRange = format.videoSupportedFrameRateRanges.first else { 
            print("❌ Failed to get suitable camera format")
            return 
        }

        print("📱 Camera format: \(format.formatDescription.dimensions.width)x\(format.formatDescription.dimensions.height)")
        print("📱 FPS range: \(fpsRange.minFrameRate)-\(fpsRange.maxFrameRate)")
        
        // Use 15fps for better performance (instead of 30fps)
        let targetFPS = min(15, Int(fpsRange.maxFrameRate))
        capturer.startCapture(with: device, format: format, fps: targetFPS)
        print("📱 Camera started at \(targetFPS) fps")
        print("📱 Camera capture started")
    }

    // MARK: – Connection Management
    
    // Background connection management
    func startBackgroundConnection() {
        print("🔄 Starting background WebRTC connection...")
        connectionState = .connecting
        
        // Start connection without exercise type
        shouldAutoReconnect = true
        callBackendWithoutExercise()
        
        // Start connection monitoring for background connection
        if connectionCheckTimer == nil {
            connectionCheckTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
                self?.checkConnectionHealth()
            }
        }
    }
    
    func startSession() {
        print("🚀 Starting WebRTC session with exercise: \(selectedExercise.rawValue)")
        
        // Start local exercise analysis
        ExerciseManager.shared.startExercise(type: selectedExercise)
        
        // If we already have a connection, just send exercise type update
        if connectionState == .connected {
            print("🚀 Connection already established, sending exercise type update")
            sendExerciseTypeUpdate()
        } else {
            print("🚀 No existing connection, creating new session")
            shouldAutoReconnect = true
            connectionState = .connecting
            callBackend()
        }
        
        // Start connection monitoring if not already running
        if connectionCheckTimer == nil {
            connectionCheckTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
                self?.checkConnectionHealth()
            }
        }
    }
    
    func pauseSession() {
        print("⏸️ Pausing exercise session (keeping connection alive)")
        // Just stop the local exercise analysis without closing connection
        ExerciseManager.shared.stopExercise()
    }
    
    func stopSession() {
        print("⏹️ Stopping WebRTC session")
        shouldAutoReconnect = false
        isConnecting = false
        
        // Stop local exercise analysis
        ExerciseManager.shared.stopExercise()
        
        // Clean up timers
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
        connectionCheckTimer?.invalidate()
        connectionCheckTimer = nil
        
        // Reset published properties
        DispatchQueue.main.async {
            self.currentRepCount = 0
            self.currentFormScore = 0
            self.currentPhase = "not_started"
            self.feedbackMessages = []
            self.latestKeypointData = nil
        }
        
        // Close data channel
        dataChannel?.close()
        dataChannel = nil
        
        // Close connection
        cleanupConnection()
    }
    
    private func cleanupConnection() {
        if let pc = pc {
            pc.close()
        }
        // Clear the remote track
        DispatchQueue.main.async {
            self.remoteTrack = nil
        }
    }
    
    private func checkConnectionHealth() {
        guard let pc = pc else { return }
        
        let iceState = pc.iceConnectionState
        let connectionState = pc.connectionState
        
        print("🔍 Connection check - ICE: \(iceState.rawValue), PC: \(connectionState.rawValue)")
        
        // Only trigger reconnection on actual failures, not normal states
        // ICE states: 0=new, 1=checking, 2=connected, 3=completed, 4=failed, 5=disconnected, 6=closed
        // PC states: 0=new, 1=connecting, 2=connected, 3=disconnected, 4=failed, 5=closed
        let iceIsFailed = iceState == .failed // 4
        let iceIsDisconnected = iceState == .disconnected // 5  
        let connectionIsFailed = connectionState == .failed // 4
        
        if (iceIsFailed || connectionIsFailed) && shouldAutoReconnect {
            print("⚠️ Connection failed (ICE: \(iceState.rawValue), PC: \(connectionState.rawValue)), triggering reconnection")
            handleConnectionFailure()
        } else if iceIsDisconnected && shouldAutoReconnect {
            print("⚠️ ICE disconnected, will monitor for potential reconnection")
            // Only reconnect after longer delay for disconnection (not immediate failure)
        }
    }
    
    private func handleConnectionFailure() {
        guard shouldAutoReconnect && !isConnecting else { return }
        
        print("🔄 Handling connection failure, will reconnect in 2 seconds")
        isConnecting = true
        
        // Clean up current connection
        cleanupConnection()
        
        // Schedule reconnection
        reconnectionTimer?.invalidate()
        reconnectionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.attemptReconnection()
        }
    }
    
    private func attemptReconnection() {
        guard shouldAutoReconnect else { return }
        
        print("🔄 Attempting reconnection...")
        isConnecting = false
        
        // Recreate peer connection with fresh instance
        createPeerConnection()
        
        // Re-add camera track
        let camTrack = factory.videoTrack(with: videoSource, trackId: "cam")
        pc.add(camTrack, streamIds: ["stream"])
        
        // Start new connection
        callBackend()
    }
    
    private func createPeerConnection() {
        let cfg = RTCConfiguration()
        cfg.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        pc = factory.peerConnection(
            with: cfg,
            constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil),
            delegate: self
        )
        
        // Create data channel for receiving keypoint data from server
        let config = RTCDataChannelConfiguration()
        config.isOrdered = true
        dataChannel = pc.dataChannel(forLabel: "keypoints", configuration: config)
        dataChannel?.delegate = self
        print("📊 Created data channel: keypoints")
    }

    // MARK: – Signalling

    func callBackend() {
        guard !isConnecting else {
            print("⚠️ Already connecting, skipping call")
            return
        }
        
        isConnecting = true
        print("📞 Calling backend...")
        
        let media = ["OfferToReceiveVideo": "true", "OfferToReceiveAudio": "true"]
        let constraints = RTCMediaConstraints(mandatoryConstraints: media, optionalConstraints: nil)

        pc.offer(for: constraints) { [weak self] offer, error in
            guard let self = self, let offer = offer else { 
                self?.isConnecting = false
                return 
            }
            self.pc.setLocalDescription(offer) { error in
                if error == nil {
                    self.postOffer(offer)
                } else {
                    self.isConnecting = false
                }
            }
        }
    }

    private func callBackendWithoutExercise() {
        guard !isConnecting else {
            print("⚠️ Already connecting, skipping call")
            return
        }
        
        isConnecting = true
        let media = ["OfferToReceiveVideo": "true", "OfferToReceiveAudio": "true"]
        let constraints = RTCMediaConstraints(mandatoryConstraints: media, optionalConstraints: nil)

        pc.offer(for: constraints) { [weak self] offer, error in
            guard let self = self, let offer = offer else { 
                self?.isConnecting = false
                return 
            }
            self.pc.setLocalDescription(offer) { error in
                if error == nil {
                    self.postOfferWithoutExercise(offer)
                } else {
                    self.isConnecting = false
                }
            }
        }
    }
    
    private func postOfferWithoutExercise(_ offer: RTCSessionDescription) {
        let body: [String: String] = [
            "sdp": offer.sdp, 
            "type": "offer"
        ]
        
        var req = URLRequest(url: URL(string: "\(serverURL)/offer")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if error != nil {
                DispatchQueue.main.async {
                    self.connectionState = .failed
                }
                return
            }
            
            guard let data = data,
                  let dict = try? JSONDecoder().decode([String: String].self, from: data),
                  let sdp = dict["sdp"], let type = dict["type"] else {
                DispatchQueue.main.async {
                    self.connectionState = .failed
                }
                return
            }
            
            let answer = RTCSessionDescription(type: type == "answer" ? .answer : .offer, sdp: sdp)
            self.pc.setRemoteDescription(answer) { [weak self] error in
                DispatchQueue.main.async {
                    self?.connectionState = error == nil ? .connected : .failed
                    self?.isConnecting = false
                }
            }
        }.resume()
    }
    
    private func postOffer(_ offer: RTCSessionDescription) {
        let body: [String: String] = [
            "sdp": offer.sdp, 
            "type": "offer",
            "exercise_type": selectedExercise.rawValue
        ]
        var req = URLRequest(url: URL(string: "\(serverURL)/offer")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, response, error in
            print("🌐 Server response received")
            
            if let error = error {
                print("❌ Network error: \(error)")
                return
            }
            
            guard let data = data else {
                print("❌ No data received")
                return
            }
            
            print("📄 Response data: \(String(data: data, encoding: .utf8) ?? "nil")")
            
            guard
                let dict = try? JSONDecoder().decode([String: String].self, from: data),
                let sdp = dict["sdp"], let type = dict["type"]
            else { 
                print("❌ Failed to decode response")
                return 
            }
            
            // Debug SDP for common issues
            print("🔍 Checking SDP for common issues...")
            if sdp.contains("pachetization-mode-") {
                print("❌ FOUND SDP TYPO: 'pachetization-mode-' instead of 'packetization-mode='")
                print("❌ This is a known issue that prevents video rendering!")
            } else if sdp.contains("packetization-mode=") {
                print("✅ SDP contains correct 'packetization-mode='")
            } else {
                print("⚠️ SDP does not contain packetization-mode parameter")
            }
            
            // Check for H.264 profile
            if sdp.contains("H264") {
                print("✅ SDP contains H.264 codec")
                if let profileRange = sdp.range(of: "profile-level-id=([a-fA-F0-9]+)", options: .regularExpression) {
                    let profile = String(sdp[profileRange])
                    print("🎥 H.264 profile: \(profile)")
                }
            } else {
                print("⚠️ SDP does not contain H.264 codec")
            }
            
            print("✅ Parsed SDP type: \(type)")
            
            let sdpType: RTCSdpType
            switch type {
            case "answer":
                sdpType = .answer
            case "offer":
                sdpType = .offer
            default:
                print("❌ Unknown SDP type: \(type)")
                return
            }

            let answer = RTCSessionDescription(type: sdpType, sdp: sdp)
            print("🔄 Setting remote description...")
            self.pc.setRemoteDescription(answer) { error in
                if let error = error {
                    print("❌ Failed to set remote description: \(error)")
                    self.isConnecting = false
                } else {
                    print("✅ Remote description set successfully")
                    self.isConnecting = false
                }
            }
        }.resume()
    }
    
    private func sendExerciseTypeUpdate() {
        // Update local exercise manager
        ExerciseManager.shared.startExercise(type: selectedExercise)
        
        guard let dataChannel = dataChannel, dataChannel.readyState == .open else {
            print("⚠️ Data channel not open for exercise type update")
            return
        }
        
        let exerciseUpdate = [
            "type": "exercise_type_update",
            "exercise_type": selectedExercise.rawValue
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exerciseUpdate)
            let buffer = RTCDataBuffer(data: jsonData, isBinary: false)
            dataChannel.sendData(buffer)
            print("📤 Sent exercise type update: \(selectedExercise.rawValue)")
        } catch {
            print("❌ Failed to send exercise type update: \(error)")
        }
    }
}

// MARK: – Delegate

extension PoseRTC: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("📺 Received media stream with \(stream.videoTracks.count) video tracks")
        if let track = stream.videoTracks.first {
            print("📺 Video track details:")
            print("📺   - trackId: \(track.trackId)")
            print("📺   - kind: \(track.kind)")
            print("📺   - isEnabled: \(track.isEnabled)")
            print("📺   - readyState: \(track.readyState.rawValue)")
            print("📺 Adding video track to UI")
            DispatchQueue.main.async { 
                print("📺 Setting remoteTrack: \(track.trackId), enabled: \(track.isEnabled), readyState: \(track.readyState.rawValue)")
                self.remoteTrack = track
                self.onRemoteTrack?(track) 
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        print("📺 Received RTP receiver with \(mediaStreams.count) streams")
        print("📺 RTP receiver details:")
        print("📺   - receiverId: \(rtpReceiver.receiverId)")
        if let track = rtpReceiver.track {
            print("📺   - track kind: \(track.kind)")
            print("📺   - track enabled: \(track.isEnabled)")
        }
        
        for stream in mediaStreams {
            if let track = stream.videoTracks.first {
                print("📺 Video track from RTP receiver:")
                print("📺   - trackId: \(track.trackId)")
                print("📺   - isEnabled: \(track.isEnabled)")
                print("📺   - readyState: \(track.readyState.rawValue)")
                print("📺 Adding video track from RTP receiver")
                DispatchQueue.main.async { 
                    print("📺 Setting remoteTrack from RTP: \(track.trackId), enabled: \(track.isEnabled), readyState: \(track.readyState.rawValue)")
                    self.remoteTrack = track
                    self.onRemoteTrack?(track) 
                }
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCPeerConnectionState) {
        print("🔗 Peer connection state: \(stateChanged.rawValue)")
        
        // Handle connection failures
        if stateChanged == .failed && shouldAutoReconnect {
            print("⚠️ Peer connection failed, triggering reconnection")
            DispatchQueue.main.async {
                self.handleConnectionFailure()
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("🧊 ICE connection state: \(newState.rawValue)")
        
        // Update connection state based on ICE state
        DispatchQueue.main.async {
            switch newState {
            case .connected, .completed:
                self.connectionState = .connected
                print("✅ Connection established - ICE state: \(newState.rawValue)")
            case .failed:
                self.connectionState = .failed
            case .checking:
                if self.connectionState != .connected {
                    self.connectionState = .connecting
                }
            default:
                break
            }
        }
        
        // Handle ICE connection failures more conservatively
        if newState == .failed && shouldAutoReconnect {
            print("⚠️ ICE connection failed, triggering reconnection")
            DispatchQueue.main.async {
                self.handleConnectionFailure()
            }
        } else if newState == .disconnected && shouldAutoReconnect {
            print("⚠️ ICE connection disconnected, will wait 10 seconds before reconnection")
            // Give it more time to potentially reconnect naturally
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if self.pc?.iceConnectionState == .disconnected && self.shouldAutoReconnect {
                    print("🔄 ICE still disconnected after 10s, triggering reconnection")
                    self.handleConnectionFailure()
                }
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCSignalingState) {
        print("📡 Signaling state: \(newState.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("📺 Removed media stream")
    }
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("🤝 Should negotiate")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        print("📺 Removed RTP receiver")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("🧊 ICE gathering state: \(newState.rawValue)")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("🧊 Generated ICE candidate")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("🧊 Removed ICE candidates")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("📊 Data channel opened: \(dataChannel.label)")
    }
}

// MARK: – RTCVideoCapturerDelegate

extension PoseRTC {
    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        frameCount += 1
        // Only log every 30th frame (every 2 seconds at 15fps)
        if frameCount % 30 == 0 {
            print("📱 Camera: \(frameCount) frames captured")
        }
        
        // Forward the frame to the video source so it can be sent via WebRTC
        videoSource.capturer(capturer, didCapture: frame)
    }
}

// MARK: – RTCDataChannelDelegate

extension PoseRTC: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("📊 Data channel state changed: \(dataChannel.readyState.rawValue)")
        if dataChannel.readyState == .open {
            print("📊 ✅ Data channel is now OPEN and ready to receive data!")
        }
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let data = Data(buffer.data)
        
        guard let jsonString = String(data: data, encoding: .utf8) else {
            print("❌ Failed to decode data channel message as UTF-8")
            return
        }
        
        print("📊 Received data channel message: \(jsonString.prefix(100))...")
        
        do {
            guard let jsonData = jsonString.data(using: String.Encoding.utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                print("❌ Failed to parse JSON from data channel")
                return
            }
            
            parseKeypointData(json)
        } catch {
            print("❌ Error parsing keypoint data: \(error)")
        }
    }
    
    private func parseKeypointData(_ json: [String: Any]) {
        guard json["type"] as? String == "keypoints" else {
            print("⚠️ Received non-keypoint data channel message")
            return
        }
        
        guard let keypointsArray = json["keypoints"] as? [[Double]],
              let confidenceArray = json["confidence"] as? [Double],
              let timestamp = json["timestamp"] as? Double else {
            print("❌ Invalid keypoint data format")
            return
        }
        
        // Get server frame dimensions if provided
        let serverWidth = json["frame_width"] as? Double ?? 720
        let serverHeight = json["frame_height"] as? Double ?? 1280
        
        print("📊 Server frame dimensions: \(serverWidth)x\(serverHeight)")
        
        // Normalize keypoints to 720x1280 coordinate space
        let targetWidth: Double = 720
        let targetHeight: Double = 1280
        let scaleX = targetWidth / serverWidth
        let scaleY = targetHeight / serverHeight
        
        let normalizedKeypoints = keypointsArray.map { keypoint in
            return [keypoint[0] * scaleX, keypoint[1] * scaleY]
        }
        
        print("📊 Scaling keypoints: \(scaleX)x\(scaleY) from \(serverWidth)x\(serverHeight) to \(targetWidth)x\(targetHeight)")
        
        // Perform local exercise analysis
        let exerciseAnalysis = ExerciseManager.shared.analyzeFrame(
            keypoints: normalizedKeypoints,
            confidence: confidenceArray
        )
        
        // Convert local analysis to ExerciseAnalysisData for compatibility
        var exerciseAnalysisData: ExerciseAnalysisData?
        if let analysis = exerciseAnalysis {
            exerciseAnalysisData = ExerciseAnalysisData(
                exerciseName: analysis.exerciseName,
                phase: analysis.phase.rawValue,
                formScore: analysis.formScore,
                repCount: analysis.repCount,
                feedbackMessages: analysis.feedbackMessages
            )
        }
        
        let keypointData = KeypointData(
            keypoints: normalizedKeypoints,  // Use normalized keypoints
            confidence: confidenceArray,
            timestamp: timestamp,
            exerciseAnalysis: exerciseAnalysisData
        )
        
        // Update published properties on main thread
        DispatchQueue.main.async {
            self.latestKeypointData = keypointData
            
            if let analysis = exerciseAnalysisData {
                self.currentRepCount = analysis.repCount
                self.currentFormScore = analysis.formScore
                self.currentPhase = analysis.phase
                self.feedbackMessages = analysis.feedbackMessages
                
                print("📊 Updated exercise stats (local): Reps=\(analysis.repCount), Form=\(analysis.formScore)%, Phase=\(analysis.phase)")
            }
        }
    }
}
