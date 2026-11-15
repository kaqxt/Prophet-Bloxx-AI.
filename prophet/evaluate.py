"""Evaluate Prophet decisions against recorded/synthetic states offline.

This module never connects to Roblox or injects controls. Feed one JSON state per
line; it reports decision/control distributions for regression testing.
"""
from __future__ import annotations

import json
import sys
from collections import Counter
from typing import Iterable

from .cli import decide


def evaluate(payloads: Iterable[dict]) -> dict:
    actions: Counter[str] = Counter()
    count = 0
    boost_count = jump_count = handbrake_count = 0
    min_steer, max_steer = 1.0, -1.0
    errors: list[dict] = []

    for index, payload in enumerate(payloads, start=1):
        try:
            result = decide(payload)
            controls = result["controls"]
            actions[result["diagnostics"]["mode"]] += 1
            boost_count += int(controls["boost"] == 1.0)
            jump_count += int(controls["jump"] == 1.0)
            handbrake_count += int(controls["handbrake"] == 1.0)
            min_steer = min(min_steer, float(controls["steer"]))
            max_steer = max(max_steer, float(controls["steer"]))
            count += 1
        except (KeyError, TypeError, ValueError) as exc:
            errors.append({"line": index, "error": str(exc)})

    return {
        "states_seen": count + len(errors),
        "states_evaluated": count,
        "invalid_states": len(errors),
        "action_counts": dict(sorted(actions.items())),
        "boost_decisions": boost_count,
        "jump_decisions": jump_count,
        "handbrake_decisions": handbrake_count,
        "steer_range": [min_steer, max_steer] if count else None,
        "errors": errors,
        "physics_validated": False,
    }


def main() -> None:
    payloads = []
    for line in sys.stdin:
        if line.strip():
            try:
                payloads.append(json.loads(line))
            except json.JSONDecodeError as exc:
                payloads.append({"_invalid_json": str(exc)})
    report = evaluate(payloads)
    print(json.dumps(report, indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
