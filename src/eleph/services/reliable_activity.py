from collections import deque
from dataclasses import dataclass
from enum import Enum
import logging
import time

from eleph.domain.activity import MotionActivityReporter
from eleph.domain.events import MotionEvent

LOGGER = logging.getLogger(__name__)


class ActivityAction(str, Enum):
    RECOVER = "recover"
    RECORD = "record"
    END = "end"


@dataclass
class PendingActivity:
    action: ActivityAction
    event: MotionEvent | None = None
    insert_motion_event: bool = False
    attempts: int = 0
    next_attempt_at: float = 0.0


class ReliableMotionActivityReporter:
    def __init__(
        self,
        *,
        primary: MotionActivityReporter,
        fallback: MotionActivityReporter,
        max_queue_size: int,
        initial_backoff_seconds: float = 1.0,
        max_backoff_seconds: float = 30.0,
    ) -> None:
        self._primary = primary
        self._fallback = fallback
        self._queue: deque[PendingActivity] = deque(maxlen=max_queue_size)
        self._initial_backoff_seconds = initial_backoff_seconds
        self._max_backoff_seconds = max_backoff_seconds

    def recover(self) -> None:
        self._enqueue(PendingActivity(action=ActivityAction.RECOVER))
        self.flush_pending()

    def record_motion(self, event: MotionEvent, *, insert_motion_event: bool) -> None:
        self._fallback.record_motion(event, insert_motion_event=insert_motion_event)
        self._enqueue(
            PendingActivity(
                action=ActivityAction.RECORD,
                event=event,
                insert_motion_event=insert_motion_event,
            )
        )
        self.flush_pending()

    def end_session(self, event: MotionEvent) -> None:
        self._fallback.end_session(event)
        self._enqueue(PendingActivity(action=ActivityAction.END, event=event))
        self.flush_pending()

    def flush_pending(self) -> None:
        now = time.monotonic()
        while self._queue:
            pending = self._queue[0]
            if pending.next_attempt_at > now:
                return

            try:
                self._send(pending)
            except Exception as exc:
                pending.attempts += 1
                backoff = min(
                    self._initial_backoff_seconds * (2 ** (pending.attempts - 1)),
                    self._max_backoff_seconds,
                )
                pending.next_attempt_at = time.monotonic() + backoff
                LOGGER.warning(
                    "motion activity upload failed; queued for retry action=%s attempts=%s "
                    "backoff_seconds=%s error=%s",
                    pending.action.value,
                    pending.attempts,
                    backoff,
                    exc,
                )
                return

            self._queue.popleft()
            LOGGER.info("motion activity upload succeeded action=%s", pending.action.value)

    def _send(self, pending: PendingActivity) -> None:
        if pending.action == ActivityAction.RECOVER:
            self._primary.recover()
            return

        if pending.event is None:
            msg = f"Activity action {pending.action.value} requires an event."
            raise RuntimeError(msg)

        if pending.action == ActivityAction.RECORD:
            self._primary.record_motion(
                pending.event,
                insert_motion_event=pending.insert_motion_event,
            )
            return

        if pending.action == ActivityAction.END:
            self._primary.end_session(pending.event)
            return

        msg = f"Unsupported motion activity action: {pending.action.value}"
        raise RuntimeError(msg)

    def _enqueue(self, pending: PendingActivity) -> None:
        if len(self._queue) == self._queue.maxlen:
            LOGGER.error("motion activity queue full; dropping oldest unsent action")
        self._queue.append(pending)
