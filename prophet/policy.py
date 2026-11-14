import numpy as np

from .prediction import estimate_intercept
from .state import GameState


class ProphetPolicy:
    def __init__(self, gravity=-196.2):
        self.gravity = gravity

    def decide(self, state: GameState):
        distance = np.linalg.norm(
            state.ball_position - state.car_position
        )

        speed = np.linalg.norm(state.car_velocity)

        travel_time = float(np.clip(
            distance / max(speed, 24.0),
            0.08,
            1.5,
        ))

        ball_target = estimate_intercept(
            state.car_position,
            state.ball_position,
            state.ball_velocity,
            travel_time,
            self.gravity,
        )

        # Approach from the side opposite the opponent's goal.
        goal_direction = state.opponent_goal - ball_target
        goal_length = np.linalg.norm(goal_direction)

        if goal_length > 1e-6:
            goal_direction /= goal_length
        else:
            goal_direction = np.array([0.0, 0.0, 1.0])

        target = ball_target - goal_direction * 5.0
        offset = target - state.car_position
        target_distance = np.linalg.norm(offset)

        direction = (
            offset / target_distance
            if target_distance > 1e-6
            else np.zeros(3)
        )

        ball_height = ball_target[1] - state.car_position[1]

        if ball_height > 7 and distance < 55:
            action = "aerial"
        elif distance < 9:
            action = "challenge"
        elif np.linalg.norm(
            state.ball_position - state.own_goal
        ) < np.linalg.norm(
            state.car_position - state.own_goal
        ):
            action = "defend"
        else:
            action = "approach"

        return {
            "action": action,
            "target_position": target.tolist(),
            "predicted_ball": ball_target.tolist(),
            "direction": direction.tolist(),
            "distance_to_ball": float(distance),
            "travel_time": travel_time,
            "boost_recommended": (
                distance > 45 and speed < 100
                and state.boost > 0
            ),
        }