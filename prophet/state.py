from dataclasses import dataclass
import numpy as np


def vec3(value):
    result = np.asarray(value, dtype=np.float64)
    if result.shape != (3,):
        raise ValueError("Expected a 3D vector")
    if not np.all(np.isfinite(result)):
        raise ValueError("Vector must contain finite numbers")
    return result


@dataclass
class GameState:
    car_position: np.ndarray
    car_velocity: np.ndarray
    ball_position: np.ndarray
    ball_velocity: np.ndarray
    opponent_goal: np.ndarray
    own_goal: np.ndarray
    boost: float = 0.0

    def __post_init__(self):
        for name in (
            "car_position",
            "car_velocity",
            "ball_position",
            "ball_velocity",
            "opponent_goal",
            "own_goal",
        ):
            setattr(self, name, vec3(getattr(self, name)))

        if not 0.0 <= self.boost <= 100.0:
            raise ValueError("Boost must be between 0 and 100")