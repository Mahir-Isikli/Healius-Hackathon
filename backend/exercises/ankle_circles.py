import numpy as np
from typing import List
import math
from .base import BaseExercise, ExerciseAnalysis, ExercisePhase


class AnkleCirclesExercise(BaseExercise):
    """
    Ankle Circles Exercise
    Track: Ankle.x, Ankle.y circular motion
    Logic: Calculate angle changes using atan2(ankle-knee)
    Timing: 0-2min establish pattern, 2-4min quality check, 4-5min count circles
    """
    
    def __init__(self):
        super().__init__()
        self.angle_history = []
        self.circle_count = 0
        self.last_quadrant = None
        self.quadrant_visits = []
        self.active_ankle = 'right'  # Start with right ankle
        
    @property
    def name(self) -> str:
        return "Ankle Circles"
    
    @property
    def description(self) -> str:
        return "Make circular motions with your ankles"
    
    @property
    def required_keypoints(self) -> List[int]:
        from server import KeypointIndex
        return [
            KeypointIndex.LEFT_ANKLE,
            KeypointIndex.RIGHT_ANKLE,
            KeypointIndex.LEFT_KNEE,
            KeypointIndex.RIGHT_KNEE
        ]
    
    def _calculate_ankle_angle(self, ankle, knee):
        """Calculate angle of ankle relative to knee"""
        dx = ankle[0] - knee[0]
        dy = ankle[1] - knee[1]
        return math.atan2(dy, dx)
    
    def _get_quadrant(self, angle):
        """Get quadrant (1-4) from angle in radians"""
        # Normalize angle to 0-2π
        normalized = angle % (2 * math.pi)
        if normalized < math.pi / 2:
            return 1
        elif normalized < math.pi:
            return 2
        elif normalized < 3 * math.pi / 2:
            return 3
        else:
            return 4
    
    def _detect_circle_completion(self, quadrant):
        """Detect if a full circle has been completed"""
        if self.last_quadrant is not None and quadrant != self.last_quadrant:
            self.quadrant_visits.append(quadrant)
            
            # Check if we've visited all 4 quadrants in sequence
            if len(self.quadrant_visits) >= 4:
                recent_quadrants = self.quadrant_visits[-4:]
                unique_quadrants = set(recent_quadrants)
                if len(unique_quadrants) == 4:
                    # Full circle detected
                    self.circle_count += 1
                    self.quadrant_visits = []  # Reset
                    return True
        
        self.last_quadrant = quadrant
        return False
    
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
                feedback_messages=["Cannot see ankles and knees clearly"],
                rep_count=self.circle_count,
                is_proper_position=False,
                confidence=0.0,
                exercise_specific_data={}
            )
        
        # Get keypoint positions
        if self.active_ankle == 'right':
            ankle = keypoints[KeypointIndex.RIGHT_ANKLE]
            knee = keypoints[KeypointIndex.RIGHT_KNEE]
        else:
            ankle = keypoints[KeypointIndex.LEFT_ANKLE]
            knee = keypoints[KeypointIndex.LEFT_KNEE]
        
        # Calculate ankle angle
        current_angle = self._calculate_ankle_angle(ankle, knee)
        current_quadrant = self._get_quadrant(current_angle)
        
        feedback_messages = []
        form_score = 70  # Base score
        
        if phase == ExercisePhase.SETUP:
            feedback_messages.append(f"Lift your {self.active_ankle} foot slightly and prepare to make circles")
            self.angle_history.append(current_angle)
            
        elif phase == ExercisePhase.ACTIVE:
            # Track angle changes
            self.angle_history.append(current_angle)
            if len(self.angle_history) > 100:
                self.angle_history.pop(0)  # Keep last 100 angles
            
            # Detect circle completion
            if self._detect_circle_completion(current_quadrant):
                feedback_messages.append(f"Circle {self.circle_count} complete!")
                form_score = 90
            else:
                # Provide guidance based on quadrant
                if current_quadrant == 1:
                    feedback_messages.append("Moving forward and out")
                elif current_quadrant == 2:
                    feedback_messages.append("Moving back and out")
                elif current_quadrant == 3:
                    feedback_messages.append("Moving back and in")
                else:
                    feedback_messages.append("Moving forward and in")
                form_score = 75
            
            # Switch ankles halfway through
            if elapsed_time > 180 and self.active_ankle == 'right':
                self.active_ankle = 'left'
                self.circle_count = 0  # Reset for left ankle
                self.quadrant_visits = []
                self.last_quadrant = None
                feedback_messages.append("Switch to left ankle circles")
                
        elif phase == ExercisePhase.COOLDOWN:
            feedback_messages.append(f"Great job! You completed {self.circle_count} ankle circles")
            form_score = 85
        
        self.rep_count = self.circle_count
        
        return ExerciseAnalysis(
            exercise_name=self.name,
            phase=phase,
            form_score=form_score,
            feedback_messages=feedback_messages,
            rep_count=self.rep_count,
            is_proper_position=True,
            confidence=min(confidence[self.required_keypoints]) * 100,
            exercise_specific_data={
                "current_angle": current_angle,
                "current_quadrant": current_quadrant,
                "active_ankle": self.active_ankle,
                "angle_history_length": len(self.angle_history)
            }
        )