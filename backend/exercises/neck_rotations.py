import numpy as np
from typing import List
from .base import BaseExercise, ExerciseAnalysis, ExercisePhase


class NeckRotationsExercise(BaseExercise):
    """
    Neck Rotations Exercise
    Track: Nose.x vs shoulder midpoint
    Logic: Nose.x moving left/right >30 pixels = rotation detected
    Timing: 0-2min left turns, 2-4min right turns, 4-5min count rotations
    """
    
    def __init__(self):
        super().__init__()
        self.shoulder_midpoint_x = None
        self.last_nose_x = None
        self.rotation_direction = None  # 'left' or 'right'
        self.left_rotations = 0
        self.right_rotations = 0
        self.rotation_threshold = 30  # pixels
        
    @property
    def name(self) -> str:
        return "Neck Rotations"
    
    @property
    def description(self) -> str:
        return "Slowly rotate your head left and right"
    
    @property
    def required_keypoints(self) -> List[int]:
        from server import KeypointIndex
        return [
            KeypointIndex.NOSE,
            KeypointIndex.LEFT_SHOULDER,
            KeypointIndex.RIGHT_SHOULDER
        ]
    
    def analyze(self, keypoints: np.ndarray, confidence: np.ndarray, elapsed_time: float) -> ExerciseAnalysis:
        from server import KeypointIndex
        
        # Update phase
        phase = self.update_phase(elapsed_time)
        
        # Check confidence
        if not self.check_confidence(confidence, self.required_keypoints):
            return ExerciseAnalysis(
                exercise_name=self.name,
                phase=phase,
                form_score=0.0,
                feedback_messages=["Cannot see face and shoulders clearly"],
                rep_count=self.left_rotations + self.right_rotations,
                is_proper_position=False,
                confidence=0.0,
                exercise_specific_data={}
            )
        
        # Get keypoint positions
        nose = keypoints[KeypointIndex.NOSE]
        left_shoulder = keypoints[KeypointIndex.LEFT_SHOULDER]
        right_shoulder = keypoints[KeypointIndex.RIGHT_SHOULDER]
        
        # Calculate shoulder midpoint
        shoulder_midpoint_x = (left_shoulder[0] + right_shoulder[0]) / 2
        
        # Track nose position relative to shoulders
        nose_offset = nose[0] - shoulder_midpoint_x
        
        feedback_messages = []
        form_score = 70  # Base score
        
        if phase == ExercisePhase.SETUP:
            self.shoulder_midpoint_x = shoulder_midpoint_x
            feedback_messages.append("Keep your shoulders still, only move your head")
            
        elif phase == ExercisePhase.ACTIVE:
            # First half: focus on left rotations
            if elapsed_time < 180:  # First 3 minutes (including setup)
                if nose_offset < -self.rotation_threshold:
                    if self.rotation_direction != 'left':
                        self.left_rotations += 1
                        self.rotation_direction = 'left'
                        feedback_messages.append(f"Left rotation {self.left_rotations}")
                        form_score = 90
                    else:
                        feedback_messages.append("Good left rotation, now slowly return to center")
                        form_score = 85
                elif nose_offset > self.rotation_threshold:
                    feedback_messages.append("Focus on rotating to your left for now")
                    form_score = 60
                else:
                    self.rotation_direction = None
                    feedback_messages.append("Now rotate your head to the left")
                    form_score = 70
            else:
                # Second half: focus on right rotations
                if nose_offset > self.rotation_threshold:
                    if self.rotation_direction != 'right':
                        self.right_rotations += 1
                        self.rotation_direction = 'right'
                        feedback_messages.append(f"Right rotation {self.right_rotations}")
                        form_score = 90
                    else:
                        feedback_messages.append("Good right rotation, now slowly return to center")
                        form_score = 85
                elif nose_offset < -self.rotation_threshold:
                    feedback_messages.append("Focus on rotating to your right for now")
                    form_score = 60
                else:
                    self.rotation_direction = None
                    feedback_messages.append("Now rotate your head to the right")
                    form_score = 70
                    
        elif phase == ExercisePhase.COOLDOWN:
            total_rotations = self.left_rotations + self.right_rotations
            feedback_messages.append(f"Excellent! {self.left_rotations} left, {self.right_rotations} right rotations")
            form_score = 85
        
        self.rep_count = self.left_rotations + self.right_rotations
        
        return ExerciseAnalysis(
            exercise_name=self.name,
            phase=phase,
            form_score=form_score,
            feedback_messages=feedback_messages,
            rep_count=self.rep_count,
            is_proper_position=True,
            confidence=min(confidence[self.required_keypoints]) * 100,
            exercise_specific_data={
                "nose_offset": nose_offset,
                "left_rotations": self.left_rotations,
                "right_rotations": self.right_rotations,
                "rotation_direction": self.rotation_direction
            }
        )