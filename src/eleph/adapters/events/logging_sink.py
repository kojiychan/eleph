import logging

from eleph.domain.events import MotionEvent

LOGGER = logging.getLogger(__name__)


class LoggingMotionEventSink:
    def record_motion(self, event: MotionEvent) -> None:
        LOGGER.info("motion event recorded locally payload=%s", event.to_supabase_payload())

    def flush_pending(self) -> None:
        return None
