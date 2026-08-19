from eleph.domain.events import MotionEvent
from eleph.domain.sinks import MotionEventSink
from eleph.services.motion_monitor import MotionMonitor


class SequenceSensor:
    def __init__(self, states: list[bool]) -> None:
        self._states = iter(states)

    def __enter__(self) -> "SequenceSensor":
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        return None

    def is_active(self) -> bool:
        return next(self._states)


class RecordingSink:
    def __init__(self) -> None:
        self.events: list[MotionEvent] = []
        self.flushes = 0

    def record_motion(self, event: MotionEvent) -> None:
        self.events.append(event)

    def flush_pending(self) -> None:
        self.flushes += 1


def build_monitor(sensor: SequenceSensor, sink: MotionEventSink) -> MotionMonitor:
    return MotionMonitor(
        sensor=sensor,
        event_sink=sink,
        device_id="test-device",
        sensor_type="infrared_obstacle",
        metadata={"gpio_pin": 17},
        poll_interval_seconds=0,
        debounce_seconds=0,
        cooldown_seconds=0,
    )


def test_motion_monitor_emits_only_inactive_to_active_transitions() -> None:
    sink = RecordingSink()
    monitor = build_monitor(
        SequenceSensor([False, True, True, False, True]),
        sink,
    )

    events = list(monitor.watch(iterations=5))

    assert len(events) == 2
    assert sink.events == events
    assert all(event.device_id == "test-device" for event in events)
    assert all(event.event_type == "motion_detected" for event in events)
    assert all(event.sensor_type == "infrared_obstacle" for event in events)
    assert all(event.metadata == {"gpio_pin": 17} for event in events)


def test_motion_monitor_flushes_pending_events_without_new_transition() -> None:
    sink = RecordingSink()
    monitor = build_monitor(SequenceSensor([False, False, False]), sink)

    events = list(monitor.watch(iterations=3))

    assert events == []
    assert sink.flushes == 3
