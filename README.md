# Prophet Bloxx AI

An experimental offline car-soccer AI research project for adapting general learning methods to Bloxx League. This project does not connect to or automate a live game client.

## Current components
- Ball trajectory prediction with configurable floor bounce, drag, and optional field bounds (`prophet/trajectory.py`)
- Physics calibration from recorded position samples and bounce velocities (`prophet/calibration.py`)
- Prediction and trial evaluation metrics (`prophet/evaluation.py`)
- A lightweight imitation-learning classifier for labeled observations (`prophet/imitation.py`)
- Heuristic intercept and offense/defense decisions (`prophet/policy.py`)
- Unit tests for prediction, calibration, evaluation, and imitation learning

## Setup

Python 3.11 or newer is recommended.

    python -m venv .venv

Activate the virtual environment, then run:

    pip install -r requirements.txt
    python -m pytest

## Training approach

The recommended progression is: calibrate the target game's physics; measure ball-prediction errors; build labeled action examples; train and compare an imitation baseline; then consider PPO/self-play only after a realistic local simulator exists. See [docs/LEARNING_PIPELINE.md](docs/LEARNING_PIPELINE.md).

The design borrows training concepts from public projects such as [Necto/Nexto](https://github.com/Rolv-Arild/Necto), [replay-pretraining](https://github.com/Rolv-Arild/replay-pretraining), and [flyguy](https://github.com/adventure-gpt/flyguy). Their Rocket League physics, weights, and action spaces are not drop-in replacements for Bloxx League.

## Limitations

- Physics parameters are provisional until calibrated from authorized observations.
- The heuristic policy is not a trained Prophet model.
- The imitation classifier needs representative labeled data and a documented feature order.
- No live-game connection, executor integration, or trained reinforcement-learning model is included.
- The internal architecture of Prophet itself is not publicly verified here.
