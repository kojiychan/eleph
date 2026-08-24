import logging

from eleph.domain.events import MotionEvent

LOGGER = logging.getLogger(__name__)


class LoggingMotionActivityReporter:
    def __init__(self) -> None:
        self._session_open = False

    def recover(self) -> None:
        LOGGER.info("motion session recovery checked locally")

    def record_motion(self, event: MotionEvent, *, insert_motion_event: bool) -> None:
        LOGGER.info("last_motion_at update device_id=%s", event.device_id)
        if insert_motion_event:
            LOGGER.info("motion_event inserted locally payload=%s", event.to_supabase_payload())
        else:
            LOGGER.info("motion_event skipped due to cooldown device_id=%s", event.device_id)
        if self._session_open:
            LOGGER.info("motion_session updated locally device_id=%s", event.device_id)
            return

        self._session_open = True
        LOGGER.info("motion_session started locally device_id=%s", event.device_id)

    def end_session(self, event: MotionEvent) -> None:
        self._session_open = False
        LOGGER.info(
            "motion_session ended locally device_id=%s ended_at=%s",
            event.device_id,
            event.detected_at.isoformat(),
        )

    def flush_pending(self) -> None:
        return None
