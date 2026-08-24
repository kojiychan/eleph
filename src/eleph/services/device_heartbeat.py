from datetime import datetime
import logging
import time

from eleph.domain.devices import DeviceStatusReporter

LOGGER = logging.getLogger(__name__)


class NullDeviceStatusReporter:
    def report_online(self, *, last_motion_at: datetime | None = None) -> None:
        return None

    def maybe_report_online(self) -> None:
        return None


class DeviceHeartbeat:
    def __init__(
        self,
        *,
        reporter: DeviceStatusReporter,
        interval_seconds: float,
    ) -> None:
        self._reporter = reporter
        self._interval_seconds = interval_seconds
        self._last_attempt_at = 0.0

    def report_startup(self) -> None:
        self.report_online()

    def report_motion(self, *, last_motion_at: datetime) -> None:
        self.report_online(last_motion_at=last_motion_at)

    def report_online(self, *, last_motion_at: datetime | None = None) -> None:
        self._send(last_motion_at=last_motion_at)

    def maybe_report_online(self) -> None:
        now = time.monotonic()
        if now - self._last_attempt_at < self._interval_seconds:
            return
        self._send(last_motion_at=None)

    def _send(self, *, last_motion_at: datetime | None) -> None:
        self._last_attempt_at = time.monotonic()
        try:
            self._reporter.report_online(last_motion_at=last_motion_at)
        except Exception as exc:
            LOGGER.warning("device heartbeat failed; will retry later error=%s", exc)
