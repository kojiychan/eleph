from typing import Protocol

from eleph.domain.events import MotionEvent


class MotionEventSink(Protocol):
    def record_motion(self, event: MotionEvent) -> None:
        ...

    def flush_pending(self) -> None:
        ...
