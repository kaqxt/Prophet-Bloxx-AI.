"""Small, dependency-light metrics for repeatable offline evaluations."""
from __future__ import annotations
import numpy as np


def trajectory_errors(predicted, observed):
    """Summarize per-step Euclidean errors for aligned 3D trajectories."""
    pred, obs = np.asarray(predicted, dtype=np.float64), np.asarray(observed, dtype=np.float64)
    if pred.shape != obs.shape or pred.ndim != 2 or pred.shape[1] != 3:
        raise ValueError("predicted and observed must have the same (N, 3) shape")
    if pred.shape[0] == 0:
        raise ValueError("trajectories must not be empty")
    if not np.all(np.isfinite(pred)) or not np.all(np.isfinite(obs)):
        raise ValueError("trajectories must contain finite values")
    errors = np.linalg.norm(pred - obs, axis=1)
    return {"mean_error": float(np.mean(errors)),
            "median_error": float(np.median(errors)),
            "p95_error": float(np.percentile(errors, 95)),
            "max_error": float(np.max(errors))}


def summarize_trials(trials):
    """Average numeric trial fields while preserving the total trial count."""
    records = list(trials)
    if not records:
        raise ValueError("at least one trial record is required")
    result = {"trial_count": len(records)}
    keys = sorted(set().union(*(record.keys() for record in records)))
    for key in keys:
        values = [record[key] for record in records if key in record]
        if values and all(isinstance(v, (int, float, bool, np.number)) for v in values):
            array = np.asarray(values, dtype=np.float64)
            if np.all(np.isfinite(array)):
                result[key + "_mean"] = float(np.mean(array))
    return result
