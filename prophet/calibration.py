"""Fit simple physics parameters from permitted recorded observations.

No game connection is implemented here. Samples should be collected from an
authorized test environment and saved as numeric observations.
"""
from __future__ import annotations
import numpy as np


def fit_vertical_gravity(samples):
    """Fit (time, vertical_position) to y(t)=c + v0*t + 0.5*g*t^2.

    Returns gravity, initial_vertical_velocity, initial_height, and RMSE.
    Use one uninterrupted, bounce-free trajectory with at least three times.
    """
    data = np.asarray(samples, dtype=np.float64)
    if data.ndim != 2 or data.shape[1] != 2 or data.shape[0] < 3:
        raise ValueError("samples must be at least three (time, height) pairs")
    if not np.all(np.isfinite(data)):
        raise ValueError("samples must contain finite values")
    t, y = data[:, 0], data[:, 1]
    if np.unique(t).size < 3:
        raise ValueError("at least three distinct times are required")
    design = np.column_stack((np.ones_like(t), t, 0.5 * t**2))
    coefficients, *_ = np.linalg.lstsq(design, y, rcond=None)
    residual = y - design @ coefficients
    return {"initial_height": float(coefficients[0]),
            "initial_vertical_velocity": float(coefficients[1]),
            "gravity": float(coefficients[2]),
            "rmse": float(np.sqrt(np.mean(residual**2)))}


def estimate_bounce_restitution(vertical_velocity_before, vertical_velocity_after):
    """Estimate |v_after| / |v_before| from one measured bounce."""
    before, after = float(vertical_velocity_before), float(vertical_velocity_after)
    if not np.isfinite(before) or not np.isfinite(after):
        raise ValueError("velocities must be finite")
    if abs(before) < 1e-8:
        raise ValueError("pre-impact velocity is too small to estimate restitution")
    ratio = abs(after) / abs(before)
    if ratio > 1.05:
        raise ValueError("estimated restitution exceeds 1.05; check measurements")
    return float(min(ratio, 1.0))
