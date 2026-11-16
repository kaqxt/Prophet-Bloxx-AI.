import numpy as np
import pytest
from prophet.imitation import ImitationPolicy


def test_imitation_policy_learns_simple_separable_actions():
    X = np.array([[-3.0], [-2.0], [-1.0], [1.0], [2.0], [3.0]])
    y = np.array(["left", "left", "left", "right", "right", "right"])
    model = ImitationPolicy(learning_rate=0.1, epochs=600, seed=2).fit(X, y)
    assert np.mean(model.predict(X) == y) >= 0.99
    assert np.allclose(model.predict_proba([[0.5]]).sum(axis=1), [1.0])


def test_imitation_policy_rejects_single_class():
    with pytest.raises(ValueError):
        ImitationPolicy(epochs=2).fit([[0.0], [1.0]], ["walk", "walk"])
