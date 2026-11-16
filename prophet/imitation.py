"""A small NumPy classifier for learning action labels from recorded examples.

This is an imitation-learning baseline, not a replacement for a calibrated
simulator or reinforcement learning. Rows of X must use a consistent,
documented observation-feature order; y contains action labels.
"""
from __future__ import annotations
import numpy as np


class ImitationPolicy:
    def __init__(self, learning_rate=0.05, epochs=500, l2=1e-4, seed=7):
        if learning_rate <= 0 or epochs < 1 or l2 < 0:
            raise ValueError("learning_rate and epochs must be positive; l2 non-negative")
        self.learning_rate = float(learning_rate)
        self.epochs = int(epochs)
        self.l2 = float(l2)
        self.seed = int(seed)
        self.mean_ = self.scale_ = self.weights_ = self.bias_ = self.classes_ = None

    def fit(self, X, y):
        X = np.asarray(X, dtype=np.float64)
        y = np.asarray(y)
        if X.ndim != 2 or X.shape[0] == 0 or y.ndim != 1 or len(y) != len(X):
            raise ValueError("X must be non-empty 2D features and y one label per row")
        if not np.all(np.isfinite(X)) or not all(str(v) for v in y):
            raise ValueError("features must be finite and labels non-empty")
        self.classes_, encoded = np.unique(y.astype(str), return_inverse=True)
        if len(self.classes_) < 2:
            raise ValueError("at least two distinct action labels are required")
        self.mean_ = X.mean(axis=0)
        self.scale_ = X.std(axis=0)
        self.scale_[self.scale_ < 1e-8] = 1.0
        Z = (X - self.mean_) / self.scale_
        one_hot = np.eye(len(self.classes_))[encoded]
        rng = np.random.default_rng(self.seed)
        self.weights_ = rng.normal(0, 0.01, (Z.shape[1], len(self.classes_)))
        self.bias_ = np.zeros(len(self.classes_))
        for _ in range(self.epochs):
            logits = Z @ self.weights_ + self.bias_
            logits -= logits.max(axis=1, keepdims=True)
            probs = np.exp(logits)
            probs /= probs.sum(axis=1, keepdims=True)
            error = (probs - one_hot) / len(Z)
            self.weights_ -= self.learning_rate * (Z.T @ error + self.l2 * self.weights_)
            self.bias_ -= self.learning_rate * error.sum(axis=0)
        return self

    def predict_proba(self, X):
        if self.weights_ is None:
            raise RuntimeError("fit must be called before prediction")
        X = np.asarray(X, dtype=np.float64)
        if X.ndim == 1:
            X = X.reshape(1, -1)
        if X.ndim != 2 or X.shape[1] != self.weights_.shape[0] or not np.all(np.isfinite(X)):
            raise ValueError("X has invalid shape or non-finite features")
        Z = (X - self.mean_) / self.scale_
        logits = Z @ self.weights_ + self.bias_
        logits -= logits.max(axis=1, keepdims=True)
        probs = np.exp(logits)
        return probs / probs.sum(axis=1, keepdims=True)

    def predict(self, X):
        indices = self.predict_proba(X).argmax(axis=1)
        return self.classes_[indices]
