import numpy as np


def predict_ball(position, velocity, time, gravity=-196.2):
    position = np.asarray(position, dtype=float)
    velocity = np.asarray(velocity, dtype=float)

    acceleration = np.array([0.0, gravity, 0.0])

    return (
        position
        + velocity * time
        + 0.5 * acceleration * time**2
    )


def estimate_intercept(
    car_position,
    ball_position,
    ball_velocity,
    travel_time,
    gravity=-196.2,
):
    return predict_ball(
        ball_position,
        ball_velocity,
        travel_time,
        gravity,
    )