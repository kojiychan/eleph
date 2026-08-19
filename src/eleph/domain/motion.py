from typing import Protocol


class MotionSensor(Protocol):
    def __enter__(self) -> "MotionSensor":
        ...

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        ...

    def is_active(self) -> bool:
        ...
