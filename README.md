# Prophet Bloxx AI

An experimental car-soccer AI research project.

## Features
- Ball trajectory prediction and intercept planning
- Offensive/defensive planning decisions
- Normalized offline control adapter (throttle, steer, jump, boost, handbrake)
- JSON-lines interface for a simulator or authorized private test harness
- Offline regression scenario evaluator
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

## Offline regression evaluator

Run the included synthetic/recorded state set:

    python -m prophet.evaluate < examples/regression_states.jsonl

It prints a JSON report with the number of valid states, action counts, boost/jump/handbrake decisions, steering range, and invalid inputs. This checks code consistency only; it does not simulate the game's physics or prove match performance.

A simulator must map these normalized controls to its own coordinate system, units, and physics. The adapter is not proof of compatibility with Bloxx League and does not connect to a live game or inject inputs.

## Current limitations
The physics model is provisional. The policy is a baseline heuristic, not a validated reproduction of Rocket League Prophet. It has not been calibrated against Bloxx League telemetry or evaluated in the target game's physics.

## Next milestones
1. Calibrate the physics model using permitted recorded observations.
2. Build a reproducible simulator and evaluation suite.
3. Train and compare policies against the baseline.
4. Integrate only through an authorized offline/private test harness.


## Vanta-style private dashboard (Roblox Studio)

The visual/configuration port is `scripts/ProphetVantaPrivateDashboard.client.lua`.
It provides Main, Bot, Visuals, Settings, and Diagnostics pages, a draggable/minimizable
window, policy-source status, assist/display toggles, prediction-horizon settings, read-only
control values, and a reset button. It listens to the existing
`ReplicatedStorage.ProphetDashboardUpdate` BindableEvent.

For a private Studio test place:

1. Put `prophet_offline_harness.lua` in a ModuleScript named `prophet_offline_harness`.
2. Put `ProphetVantaPrivateDashboard.client.lua` in a LocalScript under `StarterPlayerScripts`.
3. Put `ProphetPrivateDemo.client.lua` in a second LocalScript under `StarterPlayerScripts`.
4. Run Play in Studio. The demo feeds synthetic states to the dashboard.

The dashboard only displays returned policy outputs. Its assist/visual toggles are local
settings flags; they are not connected to live player controls or world scanning. The
“Prophet DQN Checkpoint” option is marked unavailable until a real checkpoint/runtime is
registered. Physics remains unvalidated by default.

The Vanta code excerpt supplied during integration was not the complete clean 29,555-byte
source file, so this is a private Studio UI/adapter inspired by the supplied components,
not a byte-for-byte port of the original source. The original UI source should be supplied
as a complete file before claiming exact preservation of every original callback and control.
