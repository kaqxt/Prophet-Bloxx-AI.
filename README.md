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

## APEX × Prophet tactical extension

New files on branch `prophet/offline-bot-core`:

- `scripts/apex_prophet_tactical_extension.lua` — standalone private-simulator tactical layer. It computes a bounce-aware predicted path, candidate intercept, own-goal threat, shot lane, optional pass target, teammate spacing, recovery recommendation, boost reserve, and normalized driving suggestions. It uses plain Lua tables and contains no executor APIs, live-game hooks, remote calls, or input injection.
- `scripts/apex_prophet_smoke_test.lua` — six synthetic smoke tests for baseline decisions, goal-line threat detection, high-ball handling, teammate rotation, low-boost conservation, and repeatability.

Run the Lua smoke tests from the repository root with a Lua 5.1+ interpreter:

    lua scripts/apex_prophet_smoke_test.lua

These tests have been added but have **not** been executed in this environment. Treat the new extension as unvalidated until they pass and the planner is calibrated against a private simulator.

## Current limitations

The physics model is provisional. The policy is a heuristic, not a validated reproduction of Rocket League Prophet or an implementation of a trained DQN. It has not been calibrated against Bloxx League telemetry or evaluated in the target game's physics. It is designed for a private Studio experience or offline simulator.

## Private Studio dashboard

The visual/configuration port is `scripts/ProphetVantaPrivateDashboard.client.lua`.

The Lua offline policy in `scripts/prophet_offline_harness.lua` uses a tactical state machine with kickoff, attack/intercept, challenge, carry, aerial, defend, and rotation decisions. It predicts a short ball intercept, manages boost, varies throttle while turning, considers opponent-lane pressure, and emits a cooldown-limited dodge recommendation. This is an independent private-simulator implementation inspired by general car-soccer bot patterns; it is not a port of the linked bot's complete source and is not physics-validated.

For a private Studio test place:

1. Put `prophet_offline_harness.lua` in a ModuleScript named `prophet_offline_harness`.
2. Put `ProphetVantaPrivateDashboard.client.lua` in a LocalScript under `StarterPlayerScripts`.
3. Put `ProphetPrivateDemo.client.lua` in a second LocalScript under `StarterPlayerScripts`.
4. Run Play in Studio. The demo feeds synthetic states to the dashboard.

The dashboard only displays returned policy outputs. Its assist/visual toggles are local settings flags; they are not connected to live player controls or world scanning. The “Prophet DQN Checkpoint” option is marked unavailable until a real checkpoint/runtime is registered.

The Vanta excerpt supplied during integration was not the complete clean source file, so this is a private Studio UI/adapter inspired by supplied components, not a byte-for-byte port of the original source.

## Source research notes

The supplied `Blox Spanish League` repository is a Discord bot and HTTP match-event relay; its `index.js` does not implement a car-soccer agent or expose game physics. The public `EnderDevelopment/turbo-soccer-bot` repository has `SSLBotCore.lua`, `SSLFreestyle.lua`, and `SSLBotConfig.lua`; its stated interface is a Roblox ModuleScript that reads CFrames/Vector3s and produces desired controls. I used it only as a feature checklist for independent private-simulator logic, not as code to inject into public matches.

Searches also surfaced executor-based public-match automation loaders for Turbo Soccer. Those are not appropriate dependencies for this private simulator, can change remotely, and do not establish compatibility with Bloxx League. The implementation here intentionally does not load remote scripts or reuse executor hooks.
