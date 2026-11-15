"""Convert Prophet's planner output into normalized controls for offline testing.

This module intentionally has no game-client, executor, input-injection, or network
integration. An authorized simulator or private test harness can consume the controls.
"""
from __future__ import annotations

import math
from typing import Iterable

import numpy as np

from .policy import ProphetPolicy
from .state import GameState


def _unit_ground(vector: Iterable[float]) -> np.ndarray:
    value = np.asarray(vector, dtype=float)
    ground = np.array([value[0], value[2]], dtype=float)
    norm = float(np.linalg.norm(ground))
    return ground / norm if norm > 1e-8 else np.zeros(2, dtype=float)


class ProphetController:
    """Planner + stable normalized steering/throttle/boost/jump decisions."""

    def __init__(self, policy: ProphetPolicy | None = None):
        self.policy = policy or ProphetPolicy()

    def step(self, state: GameState, car_forward=(0.0, 0.0, 1.0)) -> dict:
        plan = self.policy.decide(state)
        forward = _unit_ground(car_forward)
        desired = _unit_ground(
            np.asarray(plan["target_position"], dtype=float) - state.car_position
        )

        if np.linalg.norm(desired) < 1e-8 or np.linalg.norm(forward) < 1e-8:
            steer = 0.0
            alignment = 1.0
        else:
            cross = forward[1] * desired[0] - forward[0] * desired[1]
            dot = float(np.clip(np.dot(forward, desired), -1.0, 1.0))
            angle = math.atan2(cross, dot)
            steer = float(np.clip(angle / (math.pi / 2), -1.0, 1.0))
            alignment = dot

        distance = float(plan["distance_to_ball"])
        throttle = 1.0 if alignment > -0.25 else 0.25
        boost = bool(
            plan["boost_recommended"]
            and alignment > 0.65
            and state.boost > 0
        )
        jump = bool(plan["action"] == "aerial")

        return {
            "plan": plan,
            "controls": {
                "throttle": throttle,
                "steer": steer,
                "jump": float(jump),
                "boost": float(boost),
                "handbrake": float(abs(steer) > 0.8 and distance > 18),
            },
            "diagnostics": {
                "heading_alignment": alignment,
                "distance_to_ball": distance,
                "mode": plan["action"],
            },
        }
