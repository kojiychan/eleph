from collections.abc import Iterator
from datetime import UTC, datetime
from threading import Event
import time

from eleph.domain.activity import MotionActivityReporter
from eleph.domain.devices import DeviceStatusReporter
from eleph.domain.events import MotionEvent
from eleph.domain.motion import MotionSensor
from eleph.domain.sinks import MotionEventSink
from eleph.services.device_heartbeat import NullDeviceStatusReporter


class MotionMonitor:
    def __init__(
        self,
        *,
        sensor: MotionSensor,
        event_sink: MotionEventSink,
        device_id: str,
        sensor_type: str,
        metadata: dict[str, object],
        poll_interval_seconds: float,
        debounce_seconds: float,
        cooldown_seconds: float,
        device_status: DeviceStatusReporter | None = None,
        activity_reporter: MotionActivityReporter | None = None,
        motion_event_cooldown_seconds: float = 180.0,
        motion_session_idle_timeout_seconds: float = 180.0,
    ) -> None:
        self._sensor = sensor
        self._event_sink = event_sink
        self._device_status = device_status or NullDeviceStatusReporter()
        self._device_id = device_id
        self._sensor_type = sensor_type
        self._metadata = metadata
        self._poll_interval_seconds = poll_interval_seconds
        self._debounce_seconds = debounce_seconds
        self._cooldown_seconds = cooldown_seconds
        self._was_active = False
        self._last_event_at = 0.0
        self._activity_reporter = activity_reporter
        self._motion_event_cooldown_seconds = motion_event_cooldown_seconds
        self._motion_session_idle_timeout_seconds = motion_session_idle_timeout_seconds
        self._session_open = False
        self._last_motion_event_inserted_at = 0.0
        self._last_motion_monotonic: float | None = None
        self._last_motion_detected_at: datetime | None = None
        self._session_end_reported = False

    def watch(
        self,
        *,
        iterations: int | None = None,
        stop_event: Event | None = None,
    ) -> Iterator[MotionEvent]:
        count = 0
        self._device_status.report_online()
        if self._activity_reporter is not None:
            self._activity_reporter.recover()
        while not self._should_stop(iterations=iterations, count=count, stop_event=stop_event):
            active = self._read_debounced()
            now = time.monotonic()

            if active:
                emitted = self._record_active_motion(now)
                if emitted is not None:
                    yield emitted
            else:
                self._maybe_end_idle_session(now)
                self._event_sink.flush_pending()
                self._device_status.maybe_report_online()
                if self._activity_reporter is not None:
                    self._activity_reporter.flush_pending()

            self._was_active = active
            count += 1
            if not self._should_stop(iterations=iterations, count=count, stop_event=stop_event):
                self._sleep(stop_event)

    def _read_debounced(self) -> bool:
        first = self._sensor.is_active()
        if self._debounce_seconds <= 0:
            return first

        time.sleep(self._debounce_seconds)
        return first and self._sensor.is_active()

    def _cooldown_has_elapsed(self, now: float) -> bool:
        return now - self._last_event_at >= self._cooldown_seconds

    def _record_active_motion(self, now: float) -> MotionEvent | None:
        event = MotionEvent.detected_now(
            device_id=self._device_id,
            sensor_type=self._sensor_type,
            metadata=self._metadata,
        )
        self._last_motion_monotonic = now
        self._last_motion_detected_at = event.detected_at
        self._session_end_reported = False

        should_insert_event = self._should_insert_motion_event(now)
        if self._activity_reporter is None:
            if should_insert_event:
                self._event_sink.record_motion(event)
                self._device_status.report_online(last_motion_at=event.detected_at)
            return event if should_insert_event else None

        self._activity_reporter.record_motion(event, insert_motion_event=should_insert_event)
        if should_insert_event:
            self._last_motion_event_inserted_at = now
            self._last_event_at = now
            return event

        return None

    def _should_insert_motion_event(self, now: float) -> bool:
        if not self._session_open:
            self._session_open = True
            return True

        if now - self._last_motion_event_inserted_at >= self._motion_event_cooldown_seconds:
            return True

        return False

    def _maybe_end_idle_session(self, now: float) -> None:
        if not self._session_open or self._session_end_reported:
            return
        if self._last_motion_monotonic is None or self._last_motion_detected_at is None:
            return
        if now - self._last_motion_monotonic < self._motion_session_idle_timeout_seconds:
            return

        ended_at = self._last_motion_detected_at
        event = MotionEvent(
            device_id=self._device_id,
            event_type="motion_session_ended",
            detected_at=ended_at.astimezone(UTC),
            sensor_type=self._sensor_type,
            metadata=self._metadata,
        )
        if self._activity_reporter is not None:
            self._activity_reporter.end_session(event)
        self._session_open = False
        self._session_end_reported = True
        self._was_active = False

    def _sleep(self, stop_event: Event | None) -> None:
        if stop_event is None:
            time.sleep(self._poll_interval_seconds)
            return
        stop_event.wait(self._poll_interval_seconds)

    def _should_stop(
        self,
        *,
        iterations: int | None,
        count: int,
        stop_event: Event | None,
    ) -> bool:
        if iterations is not None and count >= iterations:
            return True
        return stop_event.is_set() if stop_event is not None else False
