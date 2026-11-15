from prophet.evaluate import evaluate


def state(**overrides):
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


def test_evaluation_counts_states_and_control_decisions():
    report = evaluate([state(), state(boost=0)])
    assert report["states_seen"] == 2
    assert report["states_evaluated"] == 2
    assert report["invalid_states"] == 0
    assert sum(report["action_counts"].values()) == 2
    assert report["steer_range"][0] >= -1
    assert report["steer_range"][1] <= 1
    assert report["physics_validated"] is False


def test_evaluation_keeps_going_after_invalid_state():
    report = evaluate([{"bad": True}, state()])
    assert report["states_seen"] == 2
    assert report["states_evaluated"] == 1
    assert report["invalid_states"] == 1
    assert report["errors"][0]["line"] == 1
