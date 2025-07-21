from .base import BaseExercise, ExerciseAnalysis, ExercisePhase
from .shoulder_squeezes import ShoulderSqueezesExercise
from .neck_rotations import NeckRotationsExercise
from .ankle_circles import AnkleCirclesExercise

# Exercise registry
EXERCISES = {
    "shoulder_squeezes": ShoulderSqueezesExercise,
    "neck_rotations": NeckRotationsExercise,
    "ankle_circles": AnkleCirclesExercise,
}

def get_exercise(exercise_type: str) -> BaseExercise:
    """Get an exercise instance by type"""
    if exercise_type not in EXERCISES:
        raise ValueError(f"Unknown exercise type: {exercise_type}")
    return EXERCISES[exercise_type]()