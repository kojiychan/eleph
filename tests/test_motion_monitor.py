from datetime import datetime

from eleph.domain.events import MotionEvent
from eleph.domain.sinks import MotionEventSink
from eleph.domain.activity import MotionActivityReporter
from eleph.services.device_heartbeat import DeviceHeartbeat
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


class RecordingStatusReporter:
    def __init__(self) -> None:
        self.online_reports = 0
        self.motion_reports: list[datetime] = []

    def report_online(self, *, last_motion_at: datetime | None = None) -> None:
        self.online_reports += 1
        if last_motion_at is not None:
            self.motion_reports.append(last_motion_at)


class RecordingActivityReporter:
    def __init__(self) -> None:
        self.recoveries = 0
        self.records: list[tuple[MotionEvent, bool]] = []
        self.ends: list[MotionEvent] = []
        self.flushes = 0

    def recover(self) -> None:
        self.recoveries += 1

    def record_motion(self, event: MotionEvent, *, insert_motion_event: bool) -> None:
        self.records.append((event, insert_motion_event))

    def end_session(self, event: MotionEvent) -> None:
        self.ends.append(event)

    def flush_pending(self) -> None:
        self.flushes += 1


def build_monitor(
    sensor: SequenceSensor,
    sink: MotionEventSink,
    heartbeat: DeviceHeartbeat | None = None,
    activity: MotionActivityReporter | None = None,
    motion_event_cooldown_seconds: float = 180,
    motion_session_idle_timeout_seconds: float = 180,
) -> MotionMonitor:
    return MotionMonitor(
        sensor=sensor,
        event_sink=sink,
        device_id="test-device",
        sensor_type="infrared_obstacle",
        metadata={"gpio_pin": 17},
        poll_interval_seconds=0,
        debounce_seconds=0,
        cooldown_seconds=0,
        device_status=heartbeat,
        activity_reporter=activity,
        motion_event_cooldown_seconds=motion_event_cooldown_seconds,
        motion_session_idle_timeout_seconds=motion_session_idle_timeout_seconds,
    )


def test_motion_monitor_throttles_continuous_motion_events() -> None:
    sink = RecordingSink()
    activity = RecordingActivityReporter()
    monitor = build_monitor(
        SequenceSensor([True, True, True, True, True]),
        sink,
        activity=activity,
    )

    events = list(monitor.watch(iterations=5))

    assert len(events) == 1
    assert sink.events == []
    assert activity.recoveries == 1
    assert len(activity.records) == 5
    assert [insert for _, insert in activity.records] == [True, False, False, False, False]
    assert activity.ends == []
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


def test_motion_monitor_reports_startup_and_motion_heartbeats() -> None:
    sink = RecordingSink()
    reporter = RecordingStatusReporter()
    heartbeat = DeviceHeartbeat(reporter=reporter, interval_seconds=60)
    monitor = build_monitor(SequenceSensor([False, True]), sink, heartbeat)

    events = list(monitor.watch(iterations=2))

    assert len(events) == 1
    assert reporter.online_reports == 2
    assert reporter.motion_reports == [events[0].detected_at]


def test_motion_monitor_reports_periodic_heartbeats_without_motion() -> None:
    sink = RecordingSink()
    reporter = RecordingStatusReporter()
    heartbeat = DeviceHeartbeat(reporter=reporter, interval_seconds=0)
    monitor = build_monitor(SequenceSensor([False, False, False]), sink, heartbeat)

    events = list(monitor.watch(iterations=3))

    assert events == []
    assert reporter.online_reports == 4
    assert reporter.motion_reports == []


def test_motion_monitor_inserts_again_after_cooldown() -> None:
    sink = RecordingSink()
    activity = RecordingActivityReporter()
    monitor = build_monitor(
        SequenceSensor([True, True, True]),
        sink,
        activity=activity,
        motion_event_cooldown_seconds=0,
    )

    events = list(monitor.watch(iterations=3))

    assert len(events) == 3
    assert [insert for _, insert in activity.records] == [True, True, True]


def test_motion_monitor_ends_idle_session_and_starts_new_one() -> None:
    sink = RecordingSink()
    activity = RecordingActivityReporter()
    monitor = build_monitor(
        SequenceSensor([True, False, True]),
        sink,
        activity=activity,
        motion_session_idle_timeout_seconds=0,
    )

    events = list(monitor.watch(iterations=3))

    assert len(events) == 2
    assert [insert for _, insert in activity.records] == [True, True]
    assert len(activity.ends) == 1
    assert activity.ends[0].event_type == "motion_session_ended"
