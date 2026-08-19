from collections import deque
from dataclasses import dataclass
import logging
import time

from eleph.domain.events import MotionEvent
from eleph.domain.sinks import MotionEventSink

LOGGER = logging.getLogger(__name__)


@dataclass
class PendingMotionEvent:
    event: MotionEvent
    attempts: int = 0
    next_attempt_at: float = 0.0


class ReliableMotionEventSink:
    def __init__(
        self,
        *,
        primary: MotionEventSink,
        fallback: MotionEventSink,
        max_queue_size: int,
        initial_backoff_seconds: float = 1.0,
        max_backoff_seconds: float = 30.0,
    ) -> None:
        self._primary = primary
        self._fallback = fallback
        self._queue: deque[PendingMotionEvent] = deque(maxlen=max_queue_size)
        self._initial_backoff_seconds = initial_backoff_seconds
        self._max_backoff_seconds = max_backoff_seconds

    def record_motion(self, event: MotionEvent) -> None:
        self._fallback.record_motion(event)
        self._enqueue(event)
        self.flush_pending()

    def flush_pending(self) -> None:
        now = time.monotonic()
        while self._queue:
            pending = self._queue[0]
            if pending.next_attempt_at > now:
                return

            try:
                self._primary.record_motion(pending.event)
            except Exception as exc:
                pending.attempts += 1
                backoff = min(
                    self._initial_backoff_seconds * (2 ** (pending.attempts - 1)),
                    self._max_backoff_seconds,
                )
                pending.next_attempt_at = time.monotonic() + backoff
                LOGGER.warning(
                    "motion upload failed; queued for retry attempts=%s backoff_seconds=%s error=%s",
                    pending.attempts,
                    backoff,
                    exc,
                )
                return

            self._queue.popleft()
            LOGGER.info("motion upload succeeded")

    def _enqueue(self, event: MotionEvent) -> None:
        if len(self._queue) == self._queue.maxlen:
            LOGGER.error("motion event queue full; dropping oldest unsent event")
        self._queue.append(PendingMotionEvent(event=event))
