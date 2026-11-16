"""Configurable ball trajectory prediction for offline testing."""
from __future__ import annotations
import numpy as np


def simulate_ball(position, velocity, duration, *, dt=1.0/30.0,
                  gravity=-196.2, floor_y=0.0, restitution=0.55,
                  horizontal_drag=0.0, bounds=None):
    """Predict positions at fixed steps using Y as vertical axis.

    bounds may be ((min_x,max_x),(min_z,max_z)); only set measured bounds.
    This simple model must be calibrated against the target game's physics.
    """
    p = np.asarray(position, dtype=np.float64).copy()
    v = np.asarray(velocity, dtype=np.float64).copy()
    if p.shape != (3,) or v.shape != (3,):
        raise ValueError("position and velocity must be 3D vectors")
    if not np.all(np.isfinite(p)) or not np.all(np.isfinite(v)):
        raise ValueError("position and velocity must be finite")
    if duration < 0 or dt <= 0:
        raise ValueError("duration must be non-negative and dt must be positive")
    if not 0 <= restitution <= 1:
        raise ValueError("restitution must be between 0 and 1")
    if horizontal_drag < 0:
        raise ValueError("horizontal_drag must be non-negative")
    points = [p.copy()]
    elapsed = 0.0
    while elapsed < duration - 1e-12:
        step = min(dt, duration - elapsed)
        v[1] += gravity * step
        p += v * step
        if p[1] < floor_y:
            p[1] = floor_y
            if v[1] < 0:
                v[1] = -v[1] * restitution
        if horizontal_drag:
            v[[0, 2]] *= max(0.0, 1.0 - horizontal_drag * step)
        if bounds is not None:
            for axis, limits in ((0, bounds[0]), (2, bounds[1])):
                low, high = map(float, limits)
                if low >= high:
                    raise ValueError("each bounds pair must have low < high")
                if p[axis] < low:
                    p[axis], v[axis] = low, abs(v[axis])
                elif p[axis] > high:
                    p[axis], v[axis] = high, -abs(v[axis])
        points.append(p.copy())
        elapsed += step
    return np.asarray(points)
