from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from eleph import __version__
from eleph.adapters.events.logging_activity import LoggingMotionActivityReporter
from eleph.adapters.events.logging_sink import LoggingMotionEventSink
from eleph.adapters.events.supabase import SupabaseMotionEventSink
from eleph.adapters.events.supabase_device_status import SupabaseDeviceStatusReporter
from eleph.adapters.events.supabase_motion_activity import SupabaseMotionActivityReporter
from eleph.adapters.sensors.c4001_i2c import C4001I2cPresenceSensor
from eleph.adapters.sensors.infrared_gpio import InfraredGpioSensor
from eleph.adapters.sensors.simulated import SimulatedMotionSensor
from eleph.config import Settings
from eleph.domain.onboarding import ProvisioningPayload, ProvisioningResult
from eleph.domain.events import MotionEvent
from eleph.domain.motion import MotionSensor
from eleph.domain.sinks import MotionEventSink
from eleph.logging_config import configure_logging
from eleph.services.device_config import DeviceConfigStore
from eleph.services.device_heartbeat import DeviceHeartbeat, NullDeviceStatusReporter
from eleph.services.onboarding import DeviceOnboardingService
from eleph.services.motion_monitor import MotionMonitor
from eleph.services.reliable_activity import ReliableMotionActivityReporter
from eleph.services.reliable_sink import ReliableMotionEventSink
from eleph.services.wifi import DryRunWifiProvisioner, NmcliWifiProvisioner


def build_sensor(settings: Settings) -> MotionSensor:
    if settings.sensor_mode == "simulated":
        return SimulatedMotionSensor()
    if settings.sensor_mode == "gpio":
        if settings.gpio_pin is None:
            msg = "GPIO sensor mode requires ELEPH_GPIO_PIN or --pin."
            raise ValueError(msg)
        return InfraredGpioSensor(pin=settings.gpio_pin, active_low=settings.sensor_active_low)
    if settings.sensor_mode == "c4001-i2c":
        return C4001I2cPresenceSensor(
            bus=settings.c4001_i2c_bus,
            address=settings.c4001_i2c_address,
            min_range_cm=settings.c4001_min_range_cm,
            max_range_cm=settings.c4001_max_range_cm,
            trigger_range_cm=settings.c4001_trigger_range_cm,
            trigger_sensitivity=settings.c4001_trigger_sensitivity,
            keep_sensitivity=settings.c4001_keep_sensitivity,
            trigger_delay_ms=settings.c4001_trigger_delay_ms,
            keep_timeout_seconds=settings.c4001_keep_timeout_seconds,
            configure_on_start=settings.c4001_configure_on_start,
        )

    msg = f"Unsupported sensor mode: {settings.sensor_mode}"
    raise ValueError(msg)


def build_event_sink(settings: Settings) -> MotionEventSink:
    logging_sink = LoggingMotionEventSink()
    if not settings.supabase_enabled:
        return logging_sink

    supabase_sink = SupabaseMotionEventSink(
        url=settings.supabase_url or "",
        key=settings.supabase_key or "",
        table=settings.supabase_motion_table,
        timeout_seconds=settings.supabase_timeout_seconds,
    )
    return ReliableMotionEventSink(
        primary=supabase_sink,
        fallback=logging_sink,
        max_queue_size=settings.event_queue_size,
    )


def post_device_heartbeat(settings: Settings, *, strict_upload: bool = False) -> None:
    configure_logging(settings.log_level)
    if not settings.supabase_enabled:
        return

    reporter = SupabaseDeviceStatusReporter(
        url=settings.supabase_url or "",
        key=settings.supabase_key or "",
        device_id=settings.device_id,
        firmware_version=__version__,
        table=settings.supabase_devices_table,
        timeout_seconds=settings.supabase_timeout_seconds,
    )
    if strict_upload:
        reporter.report_online()
        return

    DeviceHeartbeat(
        reporter=reporter,
        interval_seconds=settings.heartbeat_interval_seconds,
    ).report_startup()


def post_fake_motion(settings: Settings, *, strict_upload: bool = False) -> MotionEvent:
    configure_logging(settings.log_level)
    event = MotionEvent.detected_now(
        device_id=settings.device_id,
        sensor_type="simulated",
        metadata={
            "synthetic": True,
            "source": "scheduled_fake_motion",
            "interval_hours": 4,
        },
    )

    if strict_upload and settings.supabase_enabled:
        LoggingMotionEventSink().record_motion(event)
        SupabaseMotionEventSink(
            url=settings.supabase_url or "",
            key=settings.supabase_key or "",
            table=settings.supabase_motion_table,
            timeout_seconds=settings.supabase_timeout_seconds,
        ).record_motion(event)
        return event

    sink = build_event_sink(settings)
    sink.record_motion(event)
    sink.flush_pending()
    return event


def provision_device(
    settings: Settings,
    payload: ProvisioningPayload,
    *,
    dry_run_wifi: bool = False,
    send_heartbeat: bool = True,
) -> ProvisioningResult:
    configure_logging(settings.log_level)
    wifi_provisioner = (
        DryRunWifiProvisioner()
        if dry_run_wifi
        else NmcliWifiProvisioner(
            iface=settings.wifi_iface,
            timeout_seconds=settings.wifi_provision_timeout_seconds,
            use_sudo=settings.wifi_use_sudo,
        )
    )
    service = DeviceOnboardingService(
        settings=settings,
        config_store=DeviceConfigStore(Path(settings.device_config_path)),
        wifi_provisioner=wifi_provisioner,
        heartbeat_sender=post_device_heartbeat,
    )
    return service.provision(payload, send_heartbeat=send_heartbeat)


def sensor_type_for(settings: Settings) -> str:
    if settings.sensor_mode == "c4001-i2c":
        return "mmwave_c4001"
    if settings.sensor_mode == "gpio":
        return "infrared_obstacle"
    return "simulated"


def metadata_for(settings: Settings) -> dict[str, object]:
    if settings.sensor_mode == "gpio" and settings.gpio_pin is not None:
        return {"gpio_pin": settings.gpio_pin}
    if settings.sensor_mode == "c4001-i2c":
        return {
            "sensor_model": "DFRobot Gravity C4001 24GHz",
            "detection_profile": "human_presence_3m",
            "human_presence_target": True,
            "transport": "i2c",
            "i2c_bus": settings.c4001_i2c_bus,
            "i2c_address": f"0x{settings.c4001_i2c_address:02x}",
            "min_range_cm": settings.c4001_min_range_cm,
            "max_range_cm": settings.c4001_max_range_cm,
            "trigger_range_cm": settings.c4001_trigger_range_cm,
        }
    return {}


def build_device_heartbeat(settings: Settings) -> DeviceHeartbeat | NullDeviceStatusReporter:
    if not settings.supabase_enabled:
        return NullDeviceStatusReporter()

    return DeviceHeartbeat(
        reporter=SupabaseDeviceStatusReporter(
            url=settings.supabase_url or "",
            key=settings.supabase_key or "",
            device_id=settings.device_id,
            firmware_version=__version__,
            table=settings.supabase_devices_table,
            timeout_seconds=settings.supabase_timeout_seconds,
        ),
        interval_seconds=settings.heartbeat_interval_seconds,
    )


def build_motion_activity_reporter(settings: Settings) -> ReliableMotionActivityReporter | None:
    if not settings.supabase_enabled:
        return None

    return ReliableMotionActivityReporter(
        primary=SupabaseMotionActivityReporter(
            url=settings.supabase_url or "",
            key=settings.supabase_key or "",
            idle_timeout_seconds=settings.motion_session_idle_timeout_seconds,
            timeout_seconds=settings.supabase_timeout_seconds,
        ),
        fallback=LoggingMotionActivityReporter(),
        max_queue_size=settings.event_queue_size,
    )


@contextmanager
def build_motion_monitor(settings: Settings) -> Iterator[MotionMonitor]:
    configure_logging(settings.log_level)
    sensor = build_sensor(settings)
    sink = build_event_sink(settings)
    heartbeat = build_device_heartbeat(settings)
    activity_reporter = build_motion_activity_reporter(settings)
    with sensor:
        yield MotionMonitor(
            sensor=sensor,
            event_sink=sink,
            device_id=settings.device_id,
            sensor_type=sensor_type_for(settings),
            metadata=metadata_for(settings),
            poll_interval_seconds=settings.poll_interval_seconds,
            debounce_seconds=settings.debounce_ms / 1000,
            cooldown_seconds=settings.cooldown_seconds,
            device_status=heartbeat,
            activity_reporter=activity_reporter,
            motion_event_cooldown_seconds=settings.motion_event_cooldown_seconds,
            motion_session_idle_timeout_seconds=settings.motion_session_idle_timeout_seconds,
        )
