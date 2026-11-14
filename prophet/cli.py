"""Small JSON-lines interface for simulator and private-harness integration."""
from __future__ import annotations

import json
import sys

from .controller import ProphetController
from .state import GameState


def decide(payload: dict) -> dict:
    state = GameState(
        car_position=payload["car_position"],
        car_velocity=payload["car_velocity"],
        ball_position=payload["ball_position"],
        ball_velocity=payload["ball_velocity"],
        opponent_goal=payload["opponent_goal"],
        own_goal=payload["own_goal"],
        boost=float(payload.get("boost", 0.0)),
    )
    return ProphetController().step(
        state, car_forward=payload.get("car_forward", [0.0, 0.0, 1.0])
    )


def main() -> None:
    """Read one JSON object per line and emit one decision per line."""
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            result = decide(json.loads(line))
            print(json.dumps(result, separators=(",", ":"), allow_nan=False), flush=True)
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
            print(json.dumps({"error": str(exc)}), flush=True)


if __name__ == "__main__":
    main()
