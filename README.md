# PhysioBuddy

**A physical therapy companion that helps you perform exercises correctly using real-time pose detection and AI coaching.**

PhysioBuddy leverages the VitPose transformer model for accurate pose estimation, providing live feedback on exercise form and technique. The system runs locally on MacBook Pro M3 with 18GB RAM using the base model, with support for larger models and enhanced versions.

## 🏗️ Project Structure

```
PhysioBuddy/
├── backend/          # Python server with pose detection
├── PhysioBuddy/      # iOS Swift application
└── README.md         # This file
```

## 🖥️ Backend Setup

The backend provides real-time pose detection and analysis using VitPose transformer model.

### Prerequisites
- Python 3.11+
- UV package manager

### Installation & Setup

1. **Navigate to backend directory:**
   ```bash
   cd backend
   ```

2. **Create and activate virtual environment:**
   ```bash
   uv venv
   source .venv/bin/activate  # On macOS/Linux
   ```

3. **Install dependencies:**
   ```bash
   uv sync
   ```

4. **Run the server:**
   ```bash
   uv run server.py
   ```

5. **Set up local tunneling for development:**
   ```bash
   ngrok http 8000
   ```
   Copy the ngrok URL for use in the iOS app.

> **Note for Production:** For future development, implement a fixed URL instead of ngrok tunneling.

## 📱 iOS App Setup

The iOS application provides real-time camera feed, pose overlay, and voice coaching features.

### Requirements
- **Xcode:** Version 15.0+ 
- **iOS:** 18.4 minimum deployment target
- **Device:** iPhone with camera support
- **OpenAI API Key:** Required for voice coaching features

### Installation & Setup

1. **Open the project:**
   ```bash
   cd PhysioBuddy
   open PhysioBuddy.xcodeproj
   ```

2. **Configure API Keys and Server URL:**
   - Set `OPENAI_API_KEY` and `SERVER_URL` in Xcode build settings (User-Defined Settings)
   - These values are injected into Info.plist at build time
   
   Example Info.plist configuration:
   ```plist
   <key>OPENAI_API_KEY</key>
   <string>$(OPENAI_API_KEY)</string>
   <key>SERVER_URL</key>
   <string>$(SERVER_URL)</string>
   ```

3. **Build and Run:**
   - Select your target device
   - Build and run using Xcode (⌘+R)
   - **Note:** Do not build from terminal - use Xcode interface

### Permissions
Camera and microphone permissions are pre-configured in the Xcode project settings.

## 🎨 Assets & Media

### Asset Creation Tools
- **AI Tools:** GNIR (Generative Neural Image Reconstruction) tools
- **Audio:** 11labs Sound Effects Creator for intro and welcome audio
- **Images:** ChatGPT DALL-E for exercise illustrations and UI graphics
- **Video:** MidJourney for video generation from static images

### Media Files
- `Welcome_Audio.mp3` - Intro voice greeting
- `Welcome_Video.mp4` - Welcome screen background video
- Exercise illustrations: `Ankle_Circle.png`, `Shoulder_Shrug.png`, `Sideleg_raises.png`

## 🤖 Technical Details

### Pose Detection Model
- **Model:** VitPose (Vision Transformer for Pose Estimation)
- **Variant:** Base model optimized for real-time inference
- **Hardware:** Runs locally on MacBook Pro M3 with 18GB RAM
- **Performance:** Real-time pose detection with live feedback

### Model Capabilities
- **Current:** Base VitPose model for standard pose detection accuracy
- **Scalable:** Supports larger model variants for enhanced precision
- **Local Processing:** No cloud dependency for pose detection
- **Real-time:** Low latency feedback for exercise coaching

### System Architecture
- **Frontend:** SwiftUI iOS application with WebRTC video streaming
- **Backend:** Python FastAPI server with VitPose integration
- **Communication:** WebSocket connections for real-time pose data
- **Voice Coaching:** OpenAI Realtime API integration for audio feedback

## 🚀 Getting Started

1. **Start the backend server** (see Backend Setup above)
2. **Configure ngrok tunneling** for local development
3. **Update iOS app** with the ngrok URL
4. **Set OpenAI API key** in iOS project settings
5. **Build and run** the iOS app in Xcode
6. **Grant camera/microphone permissions** when prompted
7. **Select an exercise** and start your physiotherapy session

## 📋 Development Notes

- Backend uses UV for dependency management
- iOS app requires Xcode for building (not command line)
- Local development relies on ngrok for tunneling
- Production deployment should use fixed server URLs
- VitPose model can be upgraded for better accuracy
- Voice coaching requires active OpenAI API subscription

## 🔮 Future Enhancements

- Fixed production server URL
- Enhanced VitPose model variants
- Additional exercise types and routines
- Progress tracking and analytics
- Multi-platform support (Android, Web)