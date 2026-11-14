"""Prophet-style car-soccer AI research project."""

from .policy import ProphetPolicy
from .state import GameState

__all__ = ["ProphetPolicy", "GameState"]