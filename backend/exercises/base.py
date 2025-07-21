from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Dict, List, Tuple, Optional
from enum import Enum
import numpy as np
import math


class ExercisePhase(Enum):
    NOT_STARTED = "not_started"
    SETUP = "setup"
    ACTIVE = "active"
    COOLDOWN = "cooldown"
    COMPLETED = "completed"


@dataclass
class ExerciseAnalysis:
    """Analysis results for any exercise"""
    exercise_name: str
    phase: ExercisePhase
    form_score: float  # 0-100 percentage
    feedback_messages: List[str]
    rep_count: int
    is_proper_position: bool
    confidence: float
    exercise_specific_data: Dict  # For exercise-specific metrics


class BaseExercise(ABC):
    """Base class for all exercises"""
    
    def __init__(self):
        self.rep_count = 0
        self.start_time = None
        self.phase = ExercisePhase.NOT_STARTED
        self.confidence_threshold = 0.6
        self.phase_durations = {
            ExercisePhase.SETUP: 120,     # 2 minutes
            ExercisePhase.ACTIVE: 120,    # 2 minutes
            ExercisePhase.COOLDOWN: 60,   # 1 minute
        }
    
    @property
    @abstractmethod
    def name(self) -> str:
        """Exercise name"""
        pass
    
    @property
    @abstractmethod
    def description(self) -> str:
        """Exercise description"""
        pass
    
    @property
    @abstractmethod
    def required_keypoints(self) -> List[int]:
        """List of required keypoint indices for this exercise"""
        pass
    
    @abstractmethod
    def analyze(self, keypoints: np.ndarray, confidence: np.ndarray, elapsed_time: float) -> ExerciseAnalysis:
        """Analyze the exercise based on keypoints"""
        pass
    
    def update_phase(self, elapsed_time: float) -> ExercisePhase:
        """Update exercise phase based on elapsed time"""
        if elapsed_time < 0:
            return ExercisePhase.NOT_STARTED
        
        cumulative_time = 0
        for phase, duration in self.phase_durations.items():
            cumulative_time += duration
            if elapsed_time < cumulative_time:
                self.phase = phase
                return phase
        
        self.phase = ExercisePhase.COMPLETED
        return ExercisePhase.COMPLETED
    
    def calculate_distance(self, p1: Tuple[float, float], p2: Tuple[float, float]) -> float:
        """Calculate Euclidean distance between two points"""
        return math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)
    
    def calculate_angle(self, p1: Tuple[float, float], p2: Tuple[float, float], p3: Tuple[float, float]) -> float:
        """Calculate angle between three points (p2 is the vertex)"""
        v1 = (p1[0] - p2[0], p1[1] - p2[1])
        v2 = (p3[0] - p2[0], p3[1] - p2[1])
        
        dot_product = v1[0] * v2[0] + v1[1] * v2[1]
        
        mag1 = math.sqrt(v1[0]**2 + v1[1]**2)
        mag2 = math.sqrt(v2[0]**2 + v2[1]**2)
        
        if mag1 == 0 or mag2 == 0:
            return 0
        
        cos_angle = dot_product / (mag1 * mag2)
        cos_angle = max(-1, min(1, cos_angle))
        angle_rad = math.acos(cos_angle)
        
        return math.degrees(angle_rad)
    
    def check_confidence(self, confidence: np.ndarray, required_indices: List[int]) -> bool:
        """Check if required keypoints have sufficient confidence"""
        for idx in required_indices:
            if confidence[idx] < self.confidence_threshold:
                return False
        return True