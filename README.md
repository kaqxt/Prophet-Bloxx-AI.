# Prophet Bloxx AI

An experimental car-soccer AI research project.

## Features
- Ball trajectory prediction and intercept planning
- Offensive/defensive planning decisions
- Normalized offline control adapter (throttle, steer, jump, boost, handbrake)
- JSON-lines interface for a simulator or authorized private test harness
- Unit tests and GitHub Actions CI

## Setup
Python 3.11 or newer is recommended.

    python -m venv .venv

Activate the environment, then run:

    python -m pip install -r requirements.txt
    python -m pytest -q

## Offline controller interface

Run:

    python -m prophet.cli < examples/state.jsonl

The input is one JSON object per line with:
- `car_position`, `car_velocity`
- `ball_position`, `ball_velocity`
- `opponent_goal`, `own_goal`
- optional `car_forward` (defaults to `[0, 0, 1]`)
- optional `boost` (0–100)

Each output line contains the planner's mode and target, plus normalized controls:
- throttle: 0–1
- steer: -1–1
- jump, boost, handbrake: 0 or 1

A simulator must map these normalized controls to its own coordinate system, units, and physics. The adapter is not proof of compatibility with Bloxx League and does not connect to a live game or inject inputs.

## Current limitations
The physics model is provisional. The policy is a baseline heuristic, not a validated reproduction of Rocket League Prophet. It has not been calibrated against Bloxx League telemetry or evaluated in the target game's physics.

## Next milestones
1. Calibrate the physics model using permitted recorded observations.
2. Build a reproducible simulator and evaluation suite.
3. Train and compare policies against the baseline.
4. Integrate only through an authorized offline/private test harness.
