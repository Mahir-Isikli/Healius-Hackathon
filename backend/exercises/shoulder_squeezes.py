import numpy as np
from typing import List
from .base import BaseExercise, ExerciseAnalysis, ExercisePhase


class ShoulderSqueezesExercise(BaseExercise):
    """
    Shoulder Squeezes Exercise
    Track: Distance between L_Shoulder.x and R_Shoulder.x
    Logic: If distance decreases >20% = good squeeze
    Timing: 0-2min setup, 2-4min squeeze tracking, 4-5min count reps
    """
    
    def __init__(self):
        super().__init__()
        self.baseline_distance = None
        self.in_squeeze = False
        self.last_distance = None
        
    @property
    def name(self) -> str:
        return "Shoulder Squeezes"
    
    @property
    def description(self) -> str:
        return "Squeeze your shoulder blades together and hold, then release"
    
    @property
    def required_keypoints(self) -> List[int]:
        from server import KeypointIndex
        return [KeypointIndex.LEFT_SHOULDER, KeypointIndex.RIGHT_SHOULDER]
    
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
                feedback_messages=["Cannot see shoulders clearly"],
                rep_count=self.rep_count,
                is_proper_position=False,
                confidence=0.0,
                exercise_specific_data={}
            )
        
        # Get shoulder positions
        left_shoulder = keypoints[KeypointIndex.LEFT_SHOULDER]
        right_shoulder = keypoints[KeypointIndex.RIGHT_SHOULDER]
        
        # Calculate shoulder distance
        shoulder_distance = abs(left_shoulder[0] - right_shoulder[0])
        
        feedback_messages = []
        form_score = 70  # Base score
        
        if phase == ExercisePhase.SETUP:
            # Establish baseline
            if self.baseline_distance is None or elapsed_time < 10:
                self.baseline_distance = shoulder_distance
                feedback_messages.append("Stand tall with shoulders relaxed")
            else:
                feedback_messages.append("Get ready to squeeze your shoulder blades")
                
        elif phase == ExercisePhase.ACTIVE:
            if self.baseline_distance:
                # Calculate squeeze percentage
                squeeze_percent = (self.baseline_distance - shoulder_distance) / self.baseline_distance * 100
                
                # Detect squeeze (>20% reduction in distance)
                if squeeze_percent > 20:
                    if not self.in_squeeze:
                        self.in_squeeze = True
                        feedback_messages.append("Good squeeze! Hold for 2 seconds")
                        form_score = 90
                    else:
                        feedback_messages.append("Keep holding the squeeze")
                        form_score = 85
                else:
                    if self.in_squeeze:
                        # Just released
                        self.rep_count += 1
                        self.in_squeeze = False
                        feedback_messages.append(f"Rep {self.rep_count} complete!")
                    else:
                        feedback_messages.append("Squeeze your shoulder blades together")
                        form_score = 60
                        
        elif phase == ExercisePhase.COOLDOWN:
            feedback_messages.append(f"Great work! You completed {self.rep_count} shoulder squeezes")
            form_score = 85
        
        return ExerciseAnalysis(
            exercise_name=self.name,
            phase=phase,
            form_score=form_score,
            feedback_messages=feedback_messages,
            rep_count=self.rep_count,
            is_proper_position=True,
            confidence=min(confidence[self.required_keypoints]) * 100,
            exercise_specific_data={
                "shoulder_distance": shoulder_distance,
                "baseline_distance": self.baseline_distance,
                "in_squeeze": self.in_squeeze
            }
        )