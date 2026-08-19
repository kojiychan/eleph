from itertools import cycle


class SimulatedMotionSensor:
    """Deterministic sensor for local development without hardware."""

    def __init__(self, states: list[bool] | None = None) -> None:
        self._states = cycle(states or [False, False, True, True, False])

    def __enter__(self) -> "SimulatedMotionSensor":
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        return None

    def is_active(self) -> bool:
        return next(self._states)
