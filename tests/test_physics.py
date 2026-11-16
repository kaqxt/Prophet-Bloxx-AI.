import numpy as np
import pytest
from prophet.calibration import estimate_bounce_restitution, fit_vertical_gravity
from prophet.evaluation import trajectory_errors
from prophet.trajectory import simulate_ball


def test_fit_vertical_gravity_from_synthetic_samples():
    times = np.linspace(0, 1, 9)
    heights = 12 + 4 * times - 0.5 * 20 * times**2
    result = fit_vertical_gravity(np.column_stack((times, heights)))
    assert result["gravity"] == pytest.approx(-20)
    assert result["initial_vertical_velocity"] == pytest.approx(4)
    assert result["rmse"] < 1e-10


def test_bounce_restitution():
    assert estimate_bounce_restitution(-20, 10) == pytest.approx(0.5)


def test_trajectory_contains_initial_position_and_bounces():
    points = simulate_ball([0, 1, 0], [0, -2, 0], 0.5, dt=0.05,
                           gravity=0, floor_y=0, restitution=0.5)
    np.testing.assert_allclose(points[0], [0, 1, 0])
    assert np.all(points[:, 1] >= 0)


def test_trajectory_error_summary():
    result = trajectory_errors(np.ones((3, 3)), np.zeros((3, 3)))
    assert result["mean_error"] == pytest.approx(np.sqrt(3))
    assert result["max_error"] == pytest.approx(np.sqrt(3))


def test_invalid_calibration_rejected():
    with pytest.raises(ValueError):
        fit_vertical_gravity([(0, 1), (0, 2), (0, 3)])
