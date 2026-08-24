from typing import Protocol

from eleph.domain.events import MotionEvent


class MotionActivityReporter(Protocol):
    def recover(self) -> None:
        ...

    def record_motion(self, event: MotionEvent, *, insert_motion_event: bool) -> None:
        ...

    def end_session(self, event: MotionEvent) -> None:
        ...

    def flush_pending(self) -> None:
        ...
