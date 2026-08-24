from dataclasses import dataclass
import os
from pathlib import Path


def parse_bool(value: str | bool) -> bool:
    if isinstance(value, bool):
        return value

    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False

    msg = f"Invalid boolean value: {value}"
    raise ValueError(msg)


@dataclass(frozen=True)
class Settings:
    environment: str = "development"
    sensor_mode: str = "simulated"
    poll_interval_seconds: float = 1.0
    log_level: str = "INFO"
    device_id: str = "test-device"
    gpio_pin: int | None = None
    sensor_active_low: bool = True
    debounce_ms: int = 200
    cooldown_seconds: float = 2.0
    supabase_url: str | None = None
    supabase_key: str | None = None
    supabase_motion_table: str = "motion_events"
    supabase_devices_table: str = "devices"
    event_queue_size: int = 100
    heartbeat_interval_seconds: float = 60.0
    motion_event_cooldown_seconds: float = 180.0
    motion_session_idle_timeout_seconds: float = 180.0
    supabase_timeout_seconds: float = 3.0
    c4001_i2c_bus: int = 1
    c4001_i2c_address: int = 0x2A
    c4001_min_range_cm: int = 30
    c4001_max_range_cm: int = 300
    c4001_trigger_range_cm: int = 300
    c4001_trigger_sensitivity: int = 1
    c4001_keep_sensitivity: int = 2
    c4001_trigger_delay_ms: int = 100
    c4001_keep_timeout_seconds: float = 2.0
    c4001_configure_on_start: bool = True

    @classmethod
    def from_env(cls) -> "Settings":
        load_dotenv()
        gpio_pin = os.getenv("ELEPH_GPIO_PIN")
        return cls(
            environment=os.getenv("ELEPH_ENV", cls.environment),
            sensor_mode=os.getenv("ELEPH_SENSOR_MODE", cls.sensor_mode),
            poll_interval_seconds=float(
                os.getenv("ELEPH_POLL_INTERVAL_SECONDS", str(cls.poll_interval_seconds))
            ),
            log_level=os.getenv("ELEPH_LOG_LEVEL", cls.log_level),
            device_id=os.getenv("ELEPH_DEVICE_ID", cls.device_id),
            gpio_pin=int(gpio_pin) if gpio_pin else None,
            sensor_active_low=parse_bool(
                os.getenv("ELEPH_SENSOR_ACTIVE_LOW", str(cls.sensor_active_low))
            ),
            debounce_ms=int(os.getenv("ELEPH_DEBOUNCE_MS", str(cls.debounce_ms))),
            cooldown_seconds=float(
                os.getenv("ELEPH_COOLDOWN_SECONDS", str(cls.cooldown_seconds))
            ),
            supabase_url=os.getenv("SUPABASE_URL"),
            supabase_key=os.getenv("SUPABASE_KEY"),
            supabase_motion_table=os.getenv(
                "SUPABASE_MOTION_TABLE", cls.supabase_motion_table
            ),
            supabase_devices_table=os.getenv(
                "SUPABASE_DEVICES_TABLE", cls.supabase_devices_table
            ),
            event_queue_size=int(os.getenv("ELEPH_EVENT_QUEUE_SIZE", str(cls.event_queue_size))),
            heartbeat_interval_seconds=float(
                os.getenv("ELEPH_HEARTBEAT_INTERVAL_SECONDS", str(cls.heartbeat_interval_seconds))
            ),
            motion_event_cooldown_seconds=float(
                os.getenv(
                    "ELEPH_MOTION_EVENT_COOLDOWN_SECONDS",
                    str(cls.motion_event_cooldown_seconds),
                )
            ),
            motion_session_idle_timeout_seconds=float(
                os.getenv(
                    "ELEPH_MOTION_SESSION_IDLE_TIMEOUT_SECONDS",
                    str(cls.motion_session_idle_timeout_seconds),
                )
            ),
            supabase_timeout_seconds=float(
                os.getenv("ELEPH_SUPABASE_TIMEOUT_SECONDS", str(cls.supabase_timeout_seconds))
            ),
            c4001_i2c_bus=int(os.getenv("ELEPH_C4001_I2C_BUS", str(cls.c4001_i2c_bus))),
            c4001_i2c_address=int(
                os.getenv("ELEPH_C4001_I2C_ADDRESS", hex(cls.c4001_i2c_address)), 0
            ),
            c4001_min_range_cm=int(
                os.getenv("ELEPH_C4001_MIN_RANGE_CM", str(cls.c4001_min_range_cm))
            ),
            c4001_max_range_cm=int(
                os.getenv("ELEPH_C4001_MAX_RANGE_CM", str(cls.c4001_max_range_cm))
            ),
            c4001_trigger_range_cm=int(
                os.getenv("ELEPH_C4001_TRIGGER_RANGE_CM", str(cls.c4001_trigger_range_cm))
            ),
            c4001_trigger_sensitivity=int(
                os.getenv(
                    "ELEPH_C4001_TRIGGER_SENSITIVITY",
                    str(cls.c4001_trigger_sensitivity),
                )
            ),
            c4001_keep_sensitivity=int(
                os.getenv("ELEPH_C4001_KEEP_SENSITIVITY", str(cls.c4001_keep_sensitivity))
            ),
            c4001_trigger_delay_ms=int(
                os.getenv("ELEPH_C4001_TRIGGER_DELAY_MS", str(cls.c4001_trigger_delay_ms))
            ),
            c4001_keep_timeout_seconds=float(
                os.getenv(
                    "ELEPH_C4001_KEEP_TIMEOUT_SECONDS",
                    str(cls.c4001_keep_timeout_seconds),
                )
            ),
            c4001_configure_on_start=parse_bool(
                os.getenv(
                    "ELEPH_C4001_CONFIGURE_ON_START",
                    str(cls.c4001_configure_on_start),
                )
            ),
        )

    def with_overrides(
        self,
        *,
        sensor_mode: str | None = None,
        device_id: str | None = None,
        gpio_pin: int | None = None,
        sensor_active_low: bool | None = None,
        debounce_ms: int | None = None,
        cooldown_seconds: float | None = None,
        poll_interval_seconds: float | None = None,
        c4001_max_range_cm: int | None = None,
        c4001_trigger_range_cm: int | None = None,
    ) -> "Settings":
        return Settings(
            environment=self.environment,
            sensor_mode=sensor_mode or self.sensor_mode,
            poll_interval_seconds=(
                poll_interval_seconds
                if poll_interval_seconds is not None
                else self.poll_interval_seconds
            ),
            log_level=self.log_level,
            device_id=device_id or self.device_id,
            gpio_pin=gpio_pin if gpio_pin is not None else self.gpio_pin,
            sensor_active_low=(
                sensor_active_low if sensor_active_low is not None else self.sensor_active_low
            ),
            debounce_ms=debounce_ms if debounce_ms is not None else self.debounce_ms,
            cooldown_seconds=(
                cooldown_seconds if cooldown_seconds is not None else self.cooldown_seconds
            ),
            supabase_url=self.supabase_url,
            supabase_key=self.supabase_key,
            supabase_motion_table=self.supabase_motion_table,
            supabase_devices_table=self.supabase_devices_table,
            event_queue_size=self.event_queue_size,
            heartbeat_interval_seconds=self.heartbeat_interval_seconds,
            motion_event_cooldown_seconds=self.motion_event_cooldown_seconds,
            motion_session_idle_timeout_seconds=self.motion_session_idle_timeout_seconds,
            supabase_timeout_seconds=self.supabase_timeout_seconds,
            c4001_i2c_bus=self.c4001_i2c_bus,
            c4001_i2c_address=self.c4001_i2c_address,
            c4001_min_range_cm=self.c4001_min_range_cm,
            c4001_max_range_cm=(
                c4001_max_range_cm
                if c4001_max_range_cm is not None
                else self.c4001_max_range_cm
            ),
            c4001_trigger_range_cm=(
                c4001_trigger_range_cm
                if c4001_trigger_range_cm is not None
                else self.c4001_trigger_range_cm
            ),
            c4001_trigger_sensitivity=self.c4001_trigger_sensitivity,
            c4001_keep_sensitivity=self.c4001_keep_sensitivity,
            c4001_trigger_delay_ms=self.c4001_trigger_delay_ms,
            c4001_keep_timeout_seconds=self.c4001_keep_timeout_seconds,
            c4001_configure_on_start=self.c4001_configure_on_start,
        )

    @property
    def supabase_enabled(self) -> bool:
        return bool(self.supabase_url and self.supabase_key)

    def format_summary(self) -> str:
        return "\n".join(
            [
                f"environment={self.environment}",
                f"sensor_mode={self.sensor_mode}",
                f"poll_interval_seconds={self.poll_interval_seconds}",
                f"log_level={self.log_level}",
                f"device_id={self.device_id}",
                f"gpio_pin={self.gpio_pin}",
                f"sensor_active_low={self.sensor_active_low}",
                f"debounce_ms={self.debounce_ms}",
                f"cooldown_seconds={self.cooldown_seconds}",
                f"supabase_url_configured={self.supabase_url is not None}",
                f"supabase_key_configured={self.supabase_key is not None}",
                f"supabase_motion_table={self.supabase_motion_table}",
                f"supabase_devices_table={self.supabase_devices_table}",
                f"event_queue_size={self.event_queue_size}",
                f"heartbeat_interval_seconds={self.heartbeat_interval_seconds}",
                f"motion_event_cooldown_seconds={self.motion_event_cooldown_seconds}",
                f"motion_session_idle_timeout_seconds={self.motion_session_idle_timeout_seconds}",
                f"supabase_timeout_seconds={self.supabase_timeout_seconds}",
                f"c4001_i2c_bus={self.c4001_i2c_bus}",
                f"c4001_i2c_address=0x{self.c4001_i2c_address:02x}",
                f"c4001_min_range_cm={self.c4001_min_range_cm}",
                f"c4001_max_range_cm={self.c4001_max_range_cm}",
                f"c4001_trigger_range_cm={self.c4001_trigger_range_cm}",
                f"c4001_trigger_sensitivity={self.c4001_trigger_sensitivity}",
                f"c4001_keep_sensitivity={self.c4001_keep_sensitivity}",
                f"c4001_trigger_delay_ms={self.c4001_trigger_delay_ms}",
                f"c4001_keep_timeout_seconds={self.c4001_keep_timeout_seconds}",
                f"c4001_configure_on_start={self.c4001_configure_on_start}",
            ]
        )


def load_dotenv(path: str | Path = ".env") -> None:
    env_path = Path(path)
    if not env_path.exists():
        return

    for line in env_path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue

        key, value = stripped.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)
