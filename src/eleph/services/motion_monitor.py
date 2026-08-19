from collections.abc import Iterator
from threading import Event
import time

from eleph.domain.events import MotionEvent
from eleph.domain.motion import MotionSensor
from eleph.domain.sinks import MotionEventSink


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
    ) -> None:
        self._sensor = sensor
        self._event_sink = event_sink
        self._device_id = device_id
        self._sensor_type = sensor_type
        self._metadata = metadata
        self._poll_interval_seconds = poll_interval_seconds
        self._debounce_seconds = debounce_seconds
        self._cooldown_seconds = cooldown_seconds
        self._was_active = False
        self._last_event_at = 0.0

    def watch(
        self,
        *,
        iterations: int | None = None,
        stop_event: Event | None = None,
    ) -> Iterator[MotionEvent]:
        count = 0
        while not self._should_stop(iterations=iterations, count=count, stop_event=stop_event):
            active = self._read_debounced()
            now = time.monotonic()

            if active and not self._was_active and self._cooldown_has_elapsed(now):
                event = MotionEvent.detected_now(
                    device_id=self._device_id,
                    sensor_type=self._sensor_type,
                    metadata=self._metadata,
                )
                self._event_sink.record_motion(event)
                self._last_event_at = now
                yield event
            else:
                self._event_sink.flush_pending()

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
