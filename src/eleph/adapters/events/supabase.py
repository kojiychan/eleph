import json
import logging
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from eleph.domain.events import MotionEvent

LOGGER = logging.getLogger(__name__)


class SupabaseMotionEventSink:
    def __init__(self, *, url: str, key: str, table: str, timeout_seconds: float = 10.0) -> None:
        self._endpoint = f"{url.rstrip('/')}/rest/v1/{table}"
        self._key = key
        self._timeout_seconds = timeout_seconds

    def record_motion(self, event: MotionEvent) -> None:
        body = json.dumps(event.to_supabase_payload()).encode("utf-8")
        request = Request(
            self._endpoint,
            data=body,
            method="POST",
            headers={
                "apikey": self._key,
                "Authorization": f"Bearer {self._key}",
                "Content-Type": "application/json",
                "Prefer": "return=minimal",
            },
        )

        try:
            with urlopen(request, timeout=self._timeout_seconds) as response:
                if response.status >= 400:
                    msg = f"Supabase insert failed with HTTP {response.status}"
                    raise RuntimeError(msg)
        except HTTPError as exc:
            body_text = exc.read().decode("utf-8", errors="replace")
            LOGGER.warning("Supabase insert failed status=%s body=%s", exc.code, body_text)
            raise
        except URLError:
            LOGGER.warning("Supabase insert failed because the network is unavailable")
            raise
