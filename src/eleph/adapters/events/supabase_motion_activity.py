import json
import logging
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from eleph.domain.events import MotionEvent

LOGGER = logging.getLogger(__name__)


class SupabaseMotionActivityReporter:
    def __init__(
        self,
        *,
        url: str,
        key: str,
        idle_timeout_seconds: float,
        timeout_seconds: float = 3.0,
    ) -> None:
        base_url = url.rstrip("/")
        self._record_endpoint = f"{base_url}/rest/v1/rpc/record_device_motion"
        self._end_endpoint = f"{base_url}/rest/v1/rpc/end_motion_session"
        self._recover_endpoint = f"{base_url}/rest/v1/rpc/close_stale_motion_sessions"
        self._key = key
        self._idle_timeout_seconds = idle_timeout_seconds
        self._timeout_seconds = timeout_seconds

    def recover(self) -> None:
        response = self._post_json(
            self._recover_endpoint,
            {
                "p_idle_timeout_seconds": self._idle_timeout_seconds,
            },
        )
        closed_count = int(response.get("closed_count", 0))
        LOGGER.info("motion_session recovery checked closed_count=%s", closed_count)

    def record_motion(self, event: MotionEvent, *, insert_motion_event: bool) -> None:
        response = self._post_json(
            self._record_endpoint,
            {
                "p_device_id": event.device_id,
                "p_detected_at": event.detected_at.isoformat(),
                "p_sensor_type": event.sensor_type,
                "p_metadata": event.metadata,
                "p_insert_motion_event": insert_motion_event,
            },
        )
        LOGGER.info("last_motion_at update device_id=%s", event.device_id)
        if bool(response.get("motion_event_inserted")):
            LOGGER.info("motion_event inserted device_id=%s", event.device_id)
        else:
            LOGGER.info("motion_event skipped due to cooldown device_id=%s", event.device_id)

        session_action = response.get("session_action")
        if session_action == "started":
            LOGGER.info(
                "motion_session started device_id=%s session_id=%s",
                event.device_id,
                response.get("session_id"),
            )
        else:
            LOGGER.info(
                "motion_session updated device_id=%s session_id=%s motion_count=%s",
                event.device_id,
                response.get("session_id"),
                response.get("motion_count"),
            )

    def end_session(self, event: MotionEvent) -> None:
        response = self._post_json(
            self._end_endpoint,
            {
                "p_device_id": event.device_id,
                "p_ended_at": event.detected_at.isoformat(),
            },
        )
        if bool(response.get("ended")):
            LOGGER.info(
                "motion_session ended device_id=%s session_id=%s ended_at=%s",
                event.device_id,
                response.get("session_id"),
                event.detected_at.isoformat(),
            )
            return

        LOGGER.info("motion_session end skipped; no open session device_id=%s", event.device_id)

    def flush_pending(self) -> None:
        return None

    def _post_json(self, endpoint: str, payload: dict[str, object]) -> dict[str, object]:
        request = Request(
            endpoint,
            data=json.dumps(payload).encode("utf-8"),
            method="POST",
            headers={
                "apikey": self._key,
                "Authorization": f"Bearer {self._key}",
                "Content-Type": "application/json",
            },
        )

        try:
            with urlopen(request, timeout=self._timeout_seconds) as response:
                body = response.read().decode("utf-8")
                if response.status >= 400:
                    msg = f"Supabase motion activity failed with HTTP {response.status}"
                    raise RuntimeError(msg)
                return json.loads(body) if body else {}
        except HTTPError as exc:
            body_text = exc.read().decode("utf-8", errors="replace")
            LOGGER.warning("Supabase motion activity failed status=%s body=%s", exc.code, body_text)
            raise
        except URLError:
            LOGGER.warning("Supabase motion activity failed because the network is unavailable")
            raise
