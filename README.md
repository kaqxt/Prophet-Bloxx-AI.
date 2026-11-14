# Prophet Bloxx AI

An experimental car-soccer AI research project.

## Features
- Ball trajectory prediction
- Intercept planning
- Offensive and defensive decisions
- Unit tests for prediction and policy logic

## Setup

Python 3.11 or newer is recommended.

    python -m venv .venv

Activate the virtual environment, then run:

    pip install -r requirements.txt
    python -m pytest

## Current limitations

The physics model is provisional.
The policy is heuristic, not a trained Prophet model.
No live-game connection is included.

## Next milestones

1. Calibrate the physics model.
2. Collect permitted game-state observations.
3. Build a realistic simulator.
4. Train and evaluate a neural policy.
5. Compare predictions against recorded outcomes.