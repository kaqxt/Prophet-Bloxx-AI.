import json

from prophet.cli import decide


def sample(**overrides):
    payload = {
        "car_position": [0, 0, 0],
        "car_velocity": [0, 0, 30],
        "ball_position": [25, 0, 15],
        "ball_velocity": [0, 0, 0],
        "opponent_goal": [0, 0, 100],
        "own_goal": [0, 0, -100],
        "car_forward": [0, 0, 1],
        "boost": 60,
    }
    payload.update(overrides)
    return payload


def test_controller_outputs_normalized_controls():
    result = decide(sample())
    controls = result["controls"]
    assert 0.0 <= controls["throttle"] <= 1.0
    assert -1.0 <= controls["steer"] <= 1.0
    assert controls["jump"] in (0.0, 1.0)
    assert controls["boost"] in (0.0, 1.0)
    assert controls["handbrake"] in (0.0, 1.0)
    assert type(result["plan"]["boost_recommended"]) is bool
    json.dumps(result, allow_nan=False)


def test_controller_steers_toward_target():
    result = decide(sample(ball_position=[-30, 0, 15]))
    assert result["controls"]["steer"] < 0


def test_no_boost_when_empty():
    result = decide(sample(boost=0))
    assert result["controls"]["boost"] == 0.0


def test_invalid_state_is_reported_by_cli_boundary():
    from prophet.cli import decide
    import pytest

    with pytest.raises((KeyError, ValueError, TypeError)):
        decide({"car_position": [float("nan"), 0, 0]})
