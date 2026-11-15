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

GitHub Actions ran the six smoke tests and 15 integration/regression tests successfully on commit `0c247c20e011dbc117247c854f4bfbf973bd097d`. This validates the synthetic Lua stack only; it does not establish live-game compatibility or policy quality.

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


## APEX × Prophet offline stack

The Lua modules are a separate experimental offline/private-simulator stack. They do not read a public match, inspect live game modules, send remote events, or inject controls.

- `scripts/apex_prophet_config.lua` — validated defaults for the simplified field, ball, car, policy and scoring.
- `scripts/apex_prophet_tactical_extension.lua` — tactical decision layer: predicted trajectory, intercept selection, goal-line threat, shot/pass lane evaluation, teammate spacing, boost reserve and recovery suggestions.
- `scripts/apex_prophet_simulator.lua` — deterministic fixed-step toy simulator with simplified ball bounces, car acceleration, boost, jump/dodge suggestions, pad respawns and goal events.
- `scripts/apex_prophet_scenarios.lua` — nine repeatable synthetic scenarios plus mirroring and validation.
- `scripts/apex_prophet_control_adapter.lua` — clamps and smooths policy output into bounded data only. It is not an input injector.
- `scripts/apex_prophet_evaluator.lua` — episode metrics, aggregate summaries, candidate comparison, ranking and bootstrap intervals.
- `scripts/apex_prophet_benchmark.lua` — end-to-end offline runner with explicit axis conversion between the simulator and tactical module.
- `scripts/apex_prophet_tuner.lua` — deterministic parameter sweeps across synthetic cases; its proxy score is for experiments only, not real-game win-rate prediction.
- `scripts/apex_prophet_smoke_test.lua` — tactical-layer synthetic smoke tests.
- `scripts/apex_prophet_integration_test.lua` — module integration/regression checks.

### Run the Lua checks

From the repository root, using Lua 5.1 or newer:

```sh
lua scripts/apex_prophet_smoke_test.lua
lua scripts/apex_prophet_integration_test.lua
lua scripts/run_apex_prophet_benchmark.lua
lua scripts/run_apex_prophet_tuning.lua
```

The integration test runs the benchmark against synthetic states for a short simulated duration. The toy simulator now applies gravity to airborne cars and treats ground dodges as airborne impulses; regression checks cover jump/dodge ascent, descent, and landing, plus rejection of non-finite configuration values and invalid restitution. The expanded 18-test integration suite is awaiting a fresh GitHub Actions result. The simulator is intentionally simplified and is **not** a faithful recreation of Bloxx League physics. GitHub Actions has successfully executed the smoke and integration tests. The Python controller also had a separate JSON serialization regression caused by a NumPy boolean; the policy now casts that field to a native Python `bool`, and a regression assertion was added. The controller tests were checked locally against the fetched source, but a fresh full Python CI result for the latest commit is not yet confirmed. Do not treat synthetic pass counts as evidence of live-game performance.

### Important coordinate and deployment notes

The toy simulator uses x/y as the floor plane and z as up. The tactical layer uses x/z as the floor plane and y as up. The benchmark contains an explicit coordinate conversion. If you connect a private Studio simulator, implement and test a separate adapter for its actual units, axes, car orientation, boost-pad layout, collision behavior and goal geometry before evaluating policy quality.

The Lua and Python stacks are independent at present; this is not a production-ready integrated game client. Keep experiments in a private Studio place or offline simulator with permission. Do not paste tokens, session cookies, executor loaders or private credentials into source files.
