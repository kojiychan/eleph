from datetime import UTC, datetime
import json
import logging
import socket
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

LOGGER = logging.getLogger(__name__)


class SupabaseDeviceStatusReporter:
    def __init__(
        self,
        *,
        url: str,
        key: str,
        device_id: str,
        firmware_version: str,
        table: str,
        timeout_seconds: float = 3.0,
    ) -> None:
        endpoint = f"{url.rstrip('/')}/rest/v1/{table}"
        self._endpoint = f"{endpoint}?on_conflict=device_id"
        self._key = key
        self._device_id = device_id
        self._firmware_version = firmware_version
        self._timeout_seconds = timeout_seconds

    def report_online(self, *, last_motion_at: datetime | None = None) -> None:
        now = datetime.now(tz=UTC)
        payload: dict[str, object] = {
            "device_id": self._device_id,
            "connection_status": "online",
            "last_seen_at": now.isoformat(),
            "firmware_version": self._firmware_version,
            "ip_address": _local_ip_address(),
        }
        if last_motion_at is not None:
            payload["last_motion_at"] = last_motion_at.astimezone(UTC).isoformat()

        request = Request(
            self._endpoint,
            data=json.dumps(payload).encode("utf-8"),
            method="POST",
            headers={
                "apikey": self._key,
                "Authorization": f"Bearer {self._key}",
                "Content-Type": "application/json",
                "Prefer": "resolution=merge-duplicates,return=minimal",
            },
        )

        try:
            with urlopen(request, timeout=self._timeout_seconds) as response:
                if response.status >= 400:
                    msg = f"Supabase device heartbeat failed with HTTP {response.status}"
                    raise RuntimeError(msg)
        except HTTPError as exc:
            body_text = exc.read().decode("utf-8", errors="replace")
            LOGGER.warning("Supabase device heartbeat failed status=%s body=%s", exc.code, body_text)
            raise
        except URLError:
            LOGGER.warning("Supabase device heartbeat failed because the network is unavailable")
            raise


def _local_ip_address() -> str | None:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.settimeout(0.2)
            sock.connect(("1.1.1.1", 80))
            return str(sock.getsockname()[0])
    except OSError:
        return None
