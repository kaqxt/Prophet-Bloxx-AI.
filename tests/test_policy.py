import numpy as np

from prophet import GameState, ProphetPolicy
from prophet.prediction import predict_ball


def test_ball_prediction():
    result = predict_ball(
        [0, 10, 0],
        [10, 0, 0],
        0.5,
        gravity=0,
    )

    np.testing.assert_allclose(result, [5, 10, 0])


def test_policy_returns_valid_plan():
    state = GameState(
        car_position=np.array([0, 0, 0]),
        car_velocity=np.array([20, 0, 0]),
        ball_position=np.array([30, 2, 0]),
        ball_velocity=np.array([0, 0, 0]),
        opponent_goal=np.array([100, 0, 0]),
        own_goal=np.array([-100, 0, 0]),
        boost=50,
    )

    result = ProphetPolicy().decide(state)

    assert result["action"] in {
        "approach", "challenge", "aerial", "defend"
    }
    assert len(result["target_position"]) == 3
    assert len(result["predicted_ball"]) == 3