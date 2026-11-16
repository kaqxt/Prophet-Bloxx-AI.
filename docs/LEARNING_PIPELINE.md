# Bloxx League AI learning pipeline

This repository is an offline research scaffold. It does not connect to, inject into, or automate a live game client. Use observations from an authorized test environment and keep training/evaluation reproducible.

## What we borrow from public research

- **Nexto / Necto:** define measurable rewards and train with reinforcement learning in a fast simulator. Their Rocket League physics and weights are not drop-in replacements for Bloxx League.
- **Replay pretraining and flyguy:** first teach a policy from labeled examples, then evaluate whether reinforcement learning improves it. Imitation alone can copy mistakes and does not guarantee competitive behavior.
- **World-model research:** later, compare predicted future states with measured outcomes. Do not trust imagined rollouts until prediction error is measured.

## Recommended milestones

1. **Physics calibration.** Collect timestamped position/velocity samples for walking, jumps, dashes, aerial movement, punches, ball flight and collisions. Fit gravity from uninterrupted vertical motion; estimate bounce restitution from velocities immediately before/after impact. Split calibration and test samples by session so the test set is not leaked.
2. **Prediction baseline.** Use prophet.trajectory.simulate_ball with measured gravity, bounce response and field bounds. Compare 0.1, 0.25, 0.5 and 1.0 second predictions with recorded outcomes using prophet.evaluation.
3. **Behavior labels.** Record legal observations and an intended action label such as approach, intercept, jump, aerial, dash, punch, recover, defend or reposition. Keep labels and action definitions consistent with the target game's actual controls.
4. **Imitation baseline.** Train a small classifier on recorded examples and hold out entire sessions/opponents. Compare it to the existing heuristic before adding more complexity.
5. **Reinforcement learning.** Only after a realistic local simulator exists, use PPO/self-play with rewards for successful touches, accurate shots, defensive saves, controlled recoveries and efficient movement. Penalize wasted dashes, missed challenges, out-of-position behavior and excessive boost use. Normalize reward scales and inspect each term independently.
6. **Evaluation.** Run fixed seeds and scenario suites. Report intercept success, shot-on-target rate, aerial contact rate, recovery time, dash success, prediction error, boost spent, goals for/against and performance against fixed baseline opponents. Keep a held-out suite for every release.

## Important transfer limits

Rocket League is a car-soccer simulation; Bloxx League has different movement, collision and action semantics. Transfer training ideas and evaluation design, not assumed gravity values, action spaces, pretrained weights or exact timings. No claim about Prophet's private architecture is required for this workflow.
