# server.py
import asyncio, logging, os
import numpy as np
import cv2
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from aiortc import RTCPeerConnection, RTCSessionDescription, VideoStreamTrack
from aiortc.contrib.media import MediaBlackhole
from av import VideoFrame
import math
from dataclasses import dataclass
from typing import Dict, List, Tuple, Optional, AsyncGenerator
from enum import Enum
import json
import base64
import time
import io

from fastapi import WebSocket
from fastapi.websockets import WebSocketDisconnect

# Pose libs
import torch
from PIL import Image
from transformers import AutoProcessor, VitPoseForPoseEstimation

import os
from openai import AsyncOpenAI
from dotenv import load_dotenv

# Supervision for drawing annotations
import supervision as sv

# Exercise analysis now handled on iOS client

# Agents SDK imports for voice coaching
try:
    from agents import Agent, function_tool, set_default_openai_key
    from agents.voice import TTSModelSettings, VoicePipeline, VoicePipelineConfig, SingleAgentVoiceWorkflow, AudioInput
    AGENTS_SDK_AVAILABLE = True
except ImportError:
    print("⚠️ Agents SDK not available. Install with: pip install openai-agents 'openai-agents[voice]'")
    AGENTS_SDK_AVAILABLE = False




app = FastAPI()
pcs = set()                         # keep PCs in memory

# --- load ViTPose once -------------------------------------------------
if torch.cuda.is_available():
    device = "cuda"
elif torch.backends.mps.is_available():
    device = "mps"
else:
    device = "cpu"

print(f"Using device: {device}")
processor = AutoProcessor.from_pretrained("usyd-community/vitpose-base-simple")
model = VitPoseForPoseEstimation.from_pretrained("usyd-community/vitpose-base-simple")
model.to(device).eval()  # .half() commented out
# ----------------------------------------------------------------------

# COCO pose skeleton connections (standard 17-keypoint format)
COCO_SKELETON = [
    [16, 14], [14, 12], [17, 15], [15, 13], [12, 13],
    [6, 12], [7, 13], [6, 7], [6, 8], [7, 9],
    [8, 10], [9, 11], [2, 3], [1, 2], [1, 3],
    [2, 4], [3, 5], [4, 6], [5, 7]
]

# COCO keypoint names (17 keypoints)
COCO_KEYPOINT_NAMES = [
    "nose", "left_eye", "right_eye", "left_ear", "right_ear",
    "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
    "left_wrist", "right_wrist", "left_hip", "right_hip",
    "left_knee", "right_knee", "left_ankle", "right_ankle"
]

# Keypoint indices for easier access
class KeypointIndex:
    NOSE = 0
    LEFT_EYE = 1
    RIGHT_EYE = 2
    LEFT_EAR = 3
    RIGHT_EAR = 4
    LEFT_SHOULDER = 5
    RIGHT_SHOULDER = 6
    LEFT_ELBOW = 7
    RIGHT_ELBOW = 8
    LEFT_WRIST = 9
    RIGHT_WRIST = 10
    LEFT_HIP = 11
    RIGHT_HIP = 12
    LEFT_KNEE = 13
    RIGHT_KNEE = 14
    LEFT_ANKLE = 15
    RIGHT_ANKLE = 16

# Global data channel reference
current_data_channel = None

# WebSocket session management
active_websocket_sessions = set()

def analyze_pose_from_image(image_data: bytes):
    """
    Extract pose keypoints and exercise analysis from image data
    
    Args:
        image_data: Raw image bytes (JPEG format)
        exercise_type: Type of exercise to analyze
        
    Returns:
        dict: Keypoint data and exercise analysis
    """
    try:
        # Convert bytes to PIL Image
        img = Image.open(io.BytesIO(image_data))
        width, height = img.size
        
        # Use entire image as bounding box - format: [[x1, y1, w, h]] (COCO format)
        boxes = [[0, 0, width, height]]
        inputs = processor(images=img, boxes=[boxes], return_tensors="pt").to(device)
        
        # Add dataset_index for COCO dataset (index 0) as tensor
        inputs["dataset_index"] = torch.tensor(0, device=device)
        
        with torch.no_grad():
            outputs = model(**inputs)
        
        pose_results = processor.post_process_pose_estimation(outputs, boxes=[boxes])
        
        # Extract keypoints
        if pose_results and len(pose_results[0]) > 0:
            kp = pose_results[0][0]["keypoints"]  # First image, first person
            keypoints_xy = kp[:, :2].cpu().numpy()  # (17, 2) x,y coordinates
            confidence = np.ones(len(keypoints_xy)) * 0.8  # Default confidence of 0.8
        else:
            # No pose detected, create empty arrays
            keypoints_xy = np.zeros((17, 2))
            confidence = np.zeros(17)
        
        # Return keypoint data
        return {
            "type": "keypoints",
            "keypoints": keypoints_xy.tolist(),
            "confidence": confidence.tolist(),
            "timestamp": time.time(),
            "frame_width": width,
            "frame_height": height
        }
        
    except Exception as e:
        print(f"❌ Error analyzing pose: {e}")
        return {
            "type": "error",
            "message": str(e),
            "timestamp": time.time()
        }

# === Agents SDK Voice Coach Implementation ===
if AGENTS_SDK_AVAILABLE:
    
    # Voice system prompt for natural conversation
    voice_system_prompt = """
    CRITICAL: You MUST respond only in English. Never speak in any other language including Japanese, Chinese, Spanish, or any non-English language.
    
    [Output Structure]
    Your output will be delivered in an audio voice response, please ensure that every response meets these guidelines:
    1. Use a friendly, encouraging, and professional fitness coach tone that sounds natural when spoken aloud in English.
    2. Keep responses short and conversational—ideally one to two sentences with actionable advice in English.
    3. Use simple, clear English language that's easy to understand during exercise.
    4. Focus on encouragement and specific form corrections in English.
    5. Be motivating and supportive, helping the user improve their technique using only English words and phrases.
    """
    
    # Exercise coaching tools (stats now tracked on iOS)
    @function_tool
    def get_exercise_stats() -> dict:
        """Get current exercise statistics - now handled on iOS client."""
        return {
            "exercise": "tracked_on_ios",
            "reps": 0,
            "phase": "not_started",
            "message": "Exercise tracking now handled on iOS client"
        }
    
    @function_tool
    def reset_exercise_session() -> dict:
        """Reset the exercise session statistics - now handled on iOS client."""
        return {
            "status": "handled_on_ios",
            "message": "Exercise session management now handled on iOS client"
        }
    
    @function_tool
    def get_form_feedback() -> dict:
        """Get specific form feedback and coaching tips for the current exercise."""
        # This would typically use current pose analysis, but for demo we'll provide general advice
        tips = [
            "Focus on slow, controlled movements",
            "Keep your wrists aligned under your shoulders",
            "Engage your core throughout the movement",
            "Coordinate your breathing with the movement"
        ]
        
        return {
            "tips": tips,
            "focus_area": "spine mobility and core engagement"
        }
    
    # Define the Exercise Coach Agent
    exercise_coach_agent = Agent(
        name="MultiExerciseCoach",
        instructions=voice_system_prompt + """
        MANDATORY: Speak ONLY in English. Do not use Japanese, Chinese, Spanish, or any other language.
        
        You are an expert fitness coach specializing in physical therapy exercises. You provide guidance for:
        - Shoulder squeezes (for posture and upper back)
        - Neck rotations (for neck mobility)
        - Ankle circles (for ankle flexibility)
        
        You provide:
        - Real-time form corrections and encouragement (in English)
        - Exercise statistics and progress tracking (in English)
        - Movement guidance and technique tips (in English)
        - Motivational support during workouts (in English)
        
        Use the available tools to access current exercise data and provide personalized coaching in English.
        Keep your responses conversational, encouraging, and focused on helping the user improve their form using only English.
        
        When greeting users, briefly explain in English that you'll help them with their physical therapy exercises.
        """,
        tools=[get_exercise_stats, reset_exercise_session, get_form_feedback],
    )
    
    # Custom TTS settings for fitness coaching with explicit English language
    fitness_coach_tts_settings = TTSModelSettings(
        voice="alloy",  # Explicitly set English voice
        instructions=(
            "IMPORTANT: You MUST speak only in English. Never use any other language. "
            "Language: English only. Respond exclusively in English. "
            "Personality: Enthusiastic, supportive, and professional fitness coach. "
            "Tone: Encouraging, motivating, and clear - like a personal trainer who genuinely cares about form and progress. "
            "Pronunciation: Clear and energetic, ensuring instructions are easily understood during exercise. Use standard American English pronunciation. "
            "Tempo: Moderate pace with strategic pauses for emphasis, allowing time for the exerciser to process feedback. "
            "Emotion: Warm, confident, and motivating, creating an atmosphere of support and achievement. "
            "Accent: Standard American English accent. Do not use any foreign accents or languages."
        )
    )
    
    # Voice pipeline configuration with explicit English language settings
    voice_pipeline_config = VoicePipelineConfig(
        tts_settings=fitness_coach_tts_settings
    )
    
    class AgentVoiceCoach:
        """Simplified voice coach using Agents SDK"""
        
        def __init__(self):
            self.pipeline = None
            self.is_active = False
        
        async def start_session(self):
            """Initialize voice coaching session with English language settings"""
            if not AGENTS_SDK_AVAILABLE:
                raise Exception("Agents SDK not available. Please install: pip install openai-agents 'openai-agents[voice]'")
            
            self.pipeline = VoicePipeline(
                workflow=SingleAgentVoiceWorkflow(exercise_coach_agent),
                config=voice_pipeline_config  # This now includes explicit English language settings
            )
            self.is_active = True
            return {"status": "ready", "message": "English voice coach ready for session"}
        
        async def process_audio(self, audio_buffer: np.ndarray) -> AsyncGenerator:
            """Process audio input and stream response"""
            if not self.is_active or not self.pipeline:
                raise Exception("Voice coach session not active")
            
            # Ensure audio buffer is the right format for Agents SDK
            # AudioInput expects int16 audio data at 24kHz (based on SDK documentation)
            if audio_buffer.dtype != np.int16:
                audio_buffer = audio_buffer.astype(np.int16)
            
            try:
                audio_input = AudioInput(buffer=audio_buffer)
                result = await self.pipeline.run(audio_input)
                
                # Stream audio response
                async for event in result.stream():
                    if event.type == "voice_stream_event_audio":
                        yield event.data
            except Exception as e:
                print(f"Error in AgentVoiceCoach.process_audio: {e}")
                raise e
        
        def stop_session(self):
            """Stop the voice coaching session"""
            self.is_active = False
            self.pipeline = None

# Global voice coach instance
agent_voice_coach = AgentVoiceCoach() if AGENTS_SDK_AVAILABLE else None

def create_supervision_keypoints(keypoints_array, confidence_array):
    """
    Convert ViTPose keypoints to supervision KeyPoints format
    
    Args:
        keypoints_array: numpy array of shape (17, 2) with x,y coordinates
        confidence_array: numpy array of shape (17,) with confidence scores
    
    Returns:
        supervision KeyPoints object
    """
    # Reshape to supervision format: (1, 17, 2) for one person
    xy = keypoints_array.reshape(1, 17, 2)
    
    # Confidence scores
    confidence = confidence_array.reshape(1, 17)
    
    # Create KeyPoints object
    keypoints = sv.KeyPoints(
        xy=xy.astype(np.float32),
        confidence=confidence.astype(np.float32)
    )
    
    return keypoints

def draw_pose_annotations(frame_np, keypoints_array, confidence_array, confidence_threshold=0.3):
    """
    Draw pose annotations on frame using supervision library
    
    Args:
        frame_np: numpy array representing the frame (H, W, 3)
        keypoints_array: numpy array of shape (17, 2) with x,y coordinates  
        confidence_array: numpy array of shape (17,) with confidence scores
        confidence_threshold: minimum confidence to draw keypoint
    
    Returns:
        annotated frame as numpy array
    """
    # Convert to supervision keypoints
    keypoints = create_supervision_keypoints(keypoints_array, confidence_array)
    
    # Use default white colors
    vertex_color = sv.Color.WHITE
    edge_color = sv.Color.WHITE
    
    # Create annotators
    vertex_annotator = sv.VertexAnnotator(
        color=vertex_color,
        radius=5
    )
    
    edge_annotator = sv.EdgeAnnotator(
        color=edge_color, 
        thickness=3,
        edges=COCO_SKELETON
    )
    
    # Apply annotations
    annotated_frame = frame_np.copy()
    
    # Draw skeleton (edges between keypoints)
    annotated_frame = edge_annotator.annotate(
        scene=annotated_frame,
        key_points=keypoints
    )
    
    # Draw keypoints (vertices)
    annotated_frame = vertex_annotator.annotate(
        scene=annotated_frame,
        key_points=keypoints
    )
    # Exercise feedback now handled on iOS
    
    return annotated_frame



class PoseTrack(VideoStreamTrack):
    """Pass-through video track that also runs pose estimation and sends keypoint data via data channel."""
    def __init__(self, track, data_channel=None, enable_annotations=False, exercise_type="shoulder_squeezes"):
        super().__init__()
        self.track = track
        self.data_channel = data_channel
        self.enable_annotations = enable_annotations
        self.exercise_type = exercise_type

    async def recv(self):
        print(f"🎥 PoseTrack.recv() called - waiting for frame from client...")
        try:
            frame: VideoFrame = await self.track.recv()     # incoming video frame
            print(f"🎥 Received frame from client: {frame.width}x{frame.height}, pts={frame.pts}")
        except Exception as e:
            print(f"❌ Error receiving frame from client: {e}")
            raise
        
        # --- Pose inference with full image bounding box --------------
        img = frame.to_image()                          # PIL.Image
        width, height = img.size
        # Use entire image as bounding box - format: [[x1, y1, w, h]] (COCO format)
        boxes = [[0, 0, width, height]]
        inputs = processor(images=img, boxes=[boxes], return_tensors="pt").to(device)
        # Convert inputs to half precision to match model (commented out)
        # for key in inputs:
        #     if inputs[key].dtype == torch.float32:
        #         inputs[key] = inputs[key].half()
        # Add dataset_index for COCO dataset (index 0) as tensor
        inputs["dataset_index"] = torch.tensor(0, device=device)
        with torch.no_grad():
            outputs = model(**inputs)
            # Convert outputs back to float32 for post-processing compatibility (commented out)
            # for key in outputs:
            #     if hasattr(outputs[key], 'dtype') and outputs[key].dtype == torch.float16:
            #         outputs[key] = outputs[key].float()
        pose_results = processor.post_process_pose_estimation(outputs, boxes=[boxes])
        
        # Extract keypoints using the correct format for supervision
        if pose_results and len(pose_results[0]) > 0:
            kp = pose_results[0][0]["keypoints"]  # First image, first person
            keypoints_xy = kp[:, :2].cpu().numpy()  # (17, 2) x,y coordinates
            # ViTPose doesn't provide confidence scores per keypoint, so we'll use a default
            confidence = np.ones(len(keypoints_xy)) * 0.8  # Default confidence of 0.8
        else:
            # No pose detected, create empty arrays
            keypoints_xy = np.zeros((17, 2))
            confidence = np.zeros(17)
        
        # Exercise analysis now done on iOS client
        print(f"Detected pose with {len(keypoints_xy)} keypoints")
        
        print("key-points:", keypoints_xy)      # Debug output
        print("confidence:", confidence)
        
        # Send keypoint data via data channel to iOS (use global channel reference)
        global current_data_channel
        if current_data_channel:
            try:
                keypoint_data = {
                    "type": "keypoints",
                    "keypoints": keypoints_xy.tolist(),  # Convert numpy to list for JSON
                    "confidence": confidence.tolist(),
                    "timestamp": time.time(),
                    "frame_width": width,  # Add frame dimensions
                    "frame_height": height,
                    # Exercise analysis removed - now handled on iOS
                }
                
                import json
                message = json.dumps(keypoint_data)
                current_data_channel.send(message)
                print(f"📡 ✅ Sent keypoint data: {len(keypoints_xy)} keypoints")
            except Exception as e:
                print(f"❌ Failed to send keypoint data: {e}")
        else:
            print("⚠️ No data channel available yet")
        
        # Convert frame to numpy for annotation (fallback rendering - should be disabled)
        if self.enable_annotations:
            # Convert PIL to numpy array (RGB -> BGR for OpenCV)
            frame_np = np.array(img)
            frame_np = cv2.cvtColor(frame_np, cv2.COLOR_RGB2BGR)
            
            # Draw pose annotations
            annotated_frame = draw_pose_annotations(frame_np, keypoints_xy, confidence)
            
            # Convert back to PIL then to VideoFrame
            annotated_frame_rgb = cv2.cvtColor(annotated_frame, cv2.COLOR_BGR2RGB)
            annotated_pil = Image.fromarray(annotated_frame_rgb)
            
            # Create new VideoFrame from annotated image
            new_frame = VideoFrame.from_image(annotated_pil)
            new_frame.pts = frame.pts
            new_frame.time_base = frame.time_base
            
            print(f"🎥 Returning processed frame to client: {new_frame.width}x{new_frame.height}, pts={new_frame.pts}")
            return new_frame
        else:
            # Return original frame unchanged (raw camera feed)
            print(f"🎥 Returning original frame to client: {frame.width}x{frame.height}, pts={frame.pts}")
            return frame


@app.get("/health")
async def health_check():
    """Health check endpoint for testing deployment"""
    return JSONResponse({
        "status": "healthy",
        "device": device,
        "model_loaded": model is not None,
        "processor_loaded": processor is not None,
        "agents_sdk_available": AGENTS_SDK_AVAILABLE,
        "timestamp": time.time()
    })

@app.get("/gpu-check")
async def gpu_check():
    """GPU check endpoint for health monitoring"""
    gpu_info = {
        "cuda_available": torch.cuda.is_available(),
        "mps_available": torch.backends.mps.is_available(),
        "device": device
    }
    
    if torch.cuda.is_available():
        gpu_info["cuda_device_count"] = torch.cuda.device_count()
        gpu_info["cuda_current_device"] = torch.cuda.current_device()
        gpu_info["cuda_device_name"] = torch.cuda.get_device_name()
    
    return JSONResponse(gpu_info)

@app.get("/exercises")
async def get_exercises():
    """Get list of available exercises - deprecated, exercises now handled on iOS"""
    return JSONResponse({
        "exercises": [],
        "message": "Exercise analysis now handled on iOS client"
    })

@app.post("/offer")
async def offer(request: Request):
    params = await request.json()
    
    # Debug: Print what we received
    print(f"Received params: {params}")
    
    # Exercise type no longer needed on backend
    
    # Handle both cases: params might be the offer directly or wrapped
    if "sdp" in params and "type" in params:
        # Direct offer object
        offer = RTCSessionDescription(sdp=params["sdp"], type=params["type"])
    else:
        # Assume params is the offer object itself
        offer = RTCSessionDescription(**params)

    pc = RTCPeerConnection()
    pcs.add(pc)
    
    # Store peer connection reference globally
    global current_data_channel
    current_data_channel = None

    @pc.on("datachannel")
    def on_datachannel(channel):
        print(f"📡 Received data channel from client: {channel.label}")
        global current_data_channel
        current_data_channel = channel
        
        @channel.on("open")
        def on_open():
            print(f"📡 Data channel opened: {channel.label}")
        
        @channel.on("message")
        def on_message(message):
            print(f"📡 Received data channel message: {message}")

    @pc.on("track")
    def on_track(track):
        print(f"🎥 Backend received track: kind={track.kind}, id={track.id}")
        if track.kind == "video":
            print(f"🎥 Adding PoseTrack")
            # IMPORTANT: Disable annotations completely - send raw video only
            pose_track = PoseTrack(track, data_channel=current_data_channel, enable_annotations=False)
            pc.addTrack(pose_track)
            print(f"🎥 PoseTrack added to peer connection with data channel")
        else:
            print(f"🎵 Ignoring audio track: {track.id}")
            MediaBlackhole().addTrack(track)

    await pc.setRemoteDescription(offer)
    answer = await pc.createAnswer()
    await pc.setLocalDescription(answer)
    return JSONResponse(
        {"sdp": pc.localDescription.sdp, "type": pc.localDescription.type}
    )

@app.websocket("/pose-analysis")
async def pose_analysis_endpoint(websocket: WebSocket):
    """WebSocket endpoint for pose analysis - receives images, returns keypoint data"""
    await websocket.accept()
    print("📡 New pose analysis WebSocket connection established")
    active_websocket_sessions.add(websocket)
    
    try:
        while True:
            # Receive message from client
            message = await websocket.receive()
            
            if message["type"] == "websocket.receive":
                if "bytes" in message:
                    # Received image data
                    image_data = message["bytes"]
                    print(f"📡 Received image data: {len(image_data)} bytes")
                    
                    # Analyze pose
                    result = analyze_pose_from_image(image_data)
                    
                    # Send result back to client
                    await websocket.send_text(json.dumps(result))
                    
                elif "text" in message:
                    # Received text message
                    try:
                        data = json.loads(message["text"])
                        print(f"📡 Received text message: {data}")
                    except json.JSONDecodeError:
                        print(f"❌ Invalid JSON received: {message['text']}")
                        
    except WebSocketDisconnect:
        print("📡 Pose analysis WebSocket disconnected")
    except Exception as e:
        print(f"❌ Error in pose analysis WebSocket: {e}")
        try:
            await websocket.send_text(json.dumps({
                "type": "error",
                "message": str(e)
            }))
        except:
            pass
    finally:
        active_websocket_sessions.discard(websocket)

@app.websocket("/voice-coach-agents")
async def voice_coach_agents_endpoint(websocket: WebSocket):
    """Enhanced voice coaching using OpenAI Agents SDK"""
    await websocket.accept()
    
    if not AGENTS_SDK_AVAILABLE:
        await websocket.send_text(json.dumps({
            "type": "error",
            "message": "Agents SDK not available. Please install: pip install openai-agents 'openai-agents[voice]'"
        }))
        await websocket.close()
        return
    
    try:
        # Start voice coaching session
        session_info = await agent_voice_coach.start_session()
        await websocket.send_text(json.dumps({
            "type": "session_started",
            "data": session_info
        }))
        
        # Handle incoming audio data
        async for message in websocket.iter_text():
            try:
                data = json.loads(message)
                
                if data.get("type") == "audio_data":
                    # Convert base64 audio to numpy array with proper format for Agents SDK
                    audio_b64 = data.get("audio", "")
                    audio_bytes = base64.b64decode(audio_b64)
                    
                    # Convert PCM16 to int16 format (Agents SDK expects int16 at 24kHz)
                    pcm16_array = np.frombuffer(audio_bytes, dtype=np.int16)
                    
                    # Resample from 16kHz to 24kHz for Agents SDK
                    # Simple linear interpolation upsampling (16kHz -> 24kHz = 1.5x)
                    target_length = int(len(pcm16_array) * 1.5)
                    indices = np.linspace(0, len(pcm16_array) - 1, target_length)
                    resampled_audio = np.interp(indices, np.arange(len(pcm16_array)), pcm16_array).astype(np.int16)
                    
                    # Ensure we have a reasonable amount of audio data
                    if len(resampled_audio) > 240:  # At least 10ms at 24kHz
                        try:
                            # Process with Agents SDK and stream response
                            async for audio_chunk in agent_voice_coach.process_audio(resampled_audio):
                                # Agents SDK returns int16 at 24kHz, downsample to 16kHz for frontend
                                # Simple decimation downsampling (24kHz -> 16kHz = 2/3)
                                if len(audio_chunk) > 0:
                                    # Take every 3rd sample and keep 2 (2/3 ratio)
                                    indices = np.arange(0, len(audio_chunk), 3/2).astype(int)
                                    indices = indices[indices < len(audio_chunk)]
                                    downsampled_chunk = audio_chunk[indices]
                                    
                                    audio_b64 = base64.b64encode(downsampled_chunk.tobytes()).decode()
                                    await websocket.send_text(json.dumps({
                                        "type": "audio_response",
                                        "audio": audio_b64,
                                        "sample_rate": 16000  # Inform frontend of sample rate
                                    }))
                        except Exception as e:
                            print(f"Error processing audio with Agents SDK: {e}")
                            await websocket.send_text(json.dumps({
                                "type": "error",
                                "message": f"Audio processing error: {str(e)}"
                            }))
                
                elif data.get("type") == "stop_session":
                    break
                    
            except json.JSONDecodeError:
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "message": "Invalid JSON received"
                }))
                
    except WebSocketDisconnect:
        print("Client disconnected from voice coach")
    except Exception as e:
        print(f"Voice coach error: {e}")
        try:
            await websocket.send_text(json.dumps({
                "type": "error",
                "message": str(e)
            }))
        except:
            pass
    finally:
        if agent_voice_coach:
            agent_voice_coach.stop_session()

# Legacy WebSocket endpoint (simplified)
@app.websocket("/voice-coach")
async def voice_coach_basic_endpoint(websocket: WebSocket):
    """Basic voice coaching endpoint - redirects to Agents SDK version"""
    await websocket.accept()
    await websocket.send_text(json.dumps({
        "type": "upgrade_available",
        "message": "Enhanced voice coaching available at /voice-coach-agents endpoint with Agents SDK",
        "install_command": "pip install openai-agents 'openai-agents[voice]'"
    }))
    await websocket.close()

@app.on_event("shutdown")
async def shutdown():
    await asyncio.gather(*[pc.close() for pc in pcs])
    pcs.clear()

# Serve static files (your HTML) - mount after API routes
app.mount("/", StaticFiles(directory=".", html=True), name="static")

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    import uvicorn
    uvicorn.run("server:app", host="0.0.0.0", port=8000)
