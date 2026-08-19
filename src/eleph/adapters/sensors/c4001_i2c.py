import logging
import time
from types import ModuleType

LOGGER = logging.getLogger(__name__)

DEFAULT_I2C_ADDRESS = 0x2A
EXIST_MODE = 0

REG_STATUS = 0x00
REG_CTRL0 = 0x01
REG_CTRL1 = 0x02
REG_RESULT_STATUS = 0x10
REG_TRIG_SENSITIVITY = 0x20
REG_KEEP_SENSITIVITY = 0x21
REG_TRIG_DELAY = 0x22
REG_KEEP_TIMEOUT_L = 0x23
REG_E_MIN_RANGE_L = 0x25
REG_E_MAX_RANGE_L = 0x27
REG_E_TRIG_RANGE_L = 0x29

I2C_START_SENSOR = 0x55
I2C_SAVE_SENSOR = 0x5C
I2C_CHANGE_MODE = 0x3B


class C4001I2cPresenceSensor:
    """DFRobot Gravity C4001 mmWave presence sensor using I2C exist mode."""

    _io_attempts = 5
    _io_retry_delay_seconds = 0.1

    def __init__(
        self,
        *,
        bus: int,
        address: int,
        min_range_cm: int,
        max_range_cm: int,
        trigger_range_cm: int,
        trigger_sensitivity: int,
        keep_sensitivity: int,
        trigger_delay_ms: int,
        keep_timeout_seconds: float,
        configure_on_start: bool,
    ) -> None:
        self._bus_number = bus
        self._address = address
        self._min_range_cm = min_range_cm
        self._max_range_cm = max_range_cm
        self._trigger_range_cm = trigger_range_cm
        self._trigger_sensitivity = trigger_sensitivity
        self._keep_sensitivity = keep_sensitivity
        self._trigger_delay_ms = trigger_delay_ms
        self._keep_timeout_seconds = keep_timeout_seconds
        self._configure_on_start = configure_on_start
        self._bus: object | None = None

    def __enter__(self) -> "C4001I2cPresenceSensor":
        smbus_module = self._import_smbus()
        self._bus = smbus_module.SMBus(self._bus_number)
        if self._configure_on_start:
            self.configure()
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        close = getattr(self._bus, "close", None)
        if callable(close):
            close()

    def is_active(self) -> bool:
        result = self._read_byte(REG_RESULT_STATUS)
        return bool(result & 0x01)

    def configure(self) -> None:
        status = self._read_byte(REG_STATUS)
        work_mode = (status & 0x02) >> 1
        if work_mode != EXIST_MODE:
            self._write_control(REG_CTRL1, I2C_CHANGE_MODE, delay_seconds=1.5)

        self._write_detection_range(
            min_range_cm=self._min_range_cm,
            max_range_cm=self._max_range_cm,
            trigger_range_cm=self._trigger_range_cm,
        )
        self._write_byte(REG_TRIG_SENSITIVITY, self._trigger_sensitivity)
        self._save()
        self._write_byte(REG_KEEP_SENSITIVITY, self._keep_sensitivity)
        self._save()
        self._write_delay(
            trigger_delay_ms=self._trigger_delay_ms,
            keep_timeout_seconds=self._keep_timeout_seconds,
        )
        self._write_control(REG_CTRL0, I2C_START_SENSOR, delay_seconds=0.2)
        LOGGER.info(
            "configured C4001 mmWave sensor address=0x%02x min_cm=%s max_cm=%s trigger_cm=%s",
            self._address,
            self._min_range_cm,
            self._max_range_cm,
            self._trigger_range_cm,
        )

    def _write_detection_range(
        self,
        *,
        min_range_cm: int,
        max_range_cm: int,
        trigger_range_cm: int,
    ) -> None:
        if min_range_cm < 30:
            msg = "C4001 minimum presence range must be at least 30cm."
            raise ValueError(msg)
        if max_range_cm < 240:
            msg = "C4001 maximum presence range must be at least 240cm."
            raise ValueError(msg)
        if not min_range_cm <= trigger_range_cm <= max_range_cm:
            msg = "C4001 trigger range must be between min and max range."
            raise ValueError(msg)

        self._write_block(
            REG_E_MIN_RANGE_L,
            [
                min_range_cm & 0xFF,
                (min_range_cm >> 8) & 0xFF,
                max_range_cm & 0xFF,
                (max_range_cm >> 8) & 0xFF,
                trigger_range_cm & 0xFF,
                (trigger_range_cm >> 8) & 0xFF,
            ],
        )
        self._save()

    def _write_delay(self, *, trigger_delay_ms: int, keep_timeout_seconds: float) -> None:
        trigger_units = round(trigger_delay_ms / 10)
        keep_units = round(keep_timeout_seconds / 0.5)
        if not 0 <= trigger_units <= 200:
            msg = "C4001 trigger delay must be between 0ms and 2000ms."
            raise ValueError(msg)
        if not 4 <= keep_units <= 3000:
            msg = "C4001 keep timeout must be between 2s and 1500s."
            raise ValueError(msg)

        self._write_block(
            REG_TRIG_DELAY,
            [
                trigger_units & 0xFF,
                keep_units & 0xFF,
                (keep_units >> 8) & 0xFF,
            ],
        )
        self._save()

    def _save(self) -> None:
        self._write_control(REG_CTRL1, I2C_SAVE_SENSOR, delay_seconds=0.5)

    def _write_control(self, register: int, value: int, *, delay_seconds: float) -> None:
        self._write_byte(register, value)
        time.sleep(delay_seconds)

    def _read_byte(self, register: int) -> int:
        if self._bus is None:
            msg = "C4001 sensor must be used as a context manager before reading."
            raise RuntimeError(msg)
        for attempt in range(1, self._io_attempts + 1):
            try:
                return int(self._bus.read_byte_data(self._address, register))
            except OSError:
                if attempt == self._io_attempts:
                    raise
                LOGGER.debug(
                    "retrying C4001 I2C read address=0x%02x register=0x%02x attempt=%s",
                    self._address,
                    register,
                    attempt + 1,
                )
                time.sleep(self._io_retry_delay_seconds)

        msg = "unreachable C4001 I2C read retry state"
        raise RuntimeError(msg)

    def _write_byte(self, register: int, value: int) -> None:
        self._write_block(register, [value])

    def _write_block(self, register: int, values: list[int]) -> None:
        if self._bus is None:
            msg = "C4001 sensor must be used as a context manager before writing."
            raise RuntimeError(msg)
        for attempt in range(1, self._io_attempts + 1):
            try:
                self._bus.write_i2c_block_data(self._address, register, values)
                return
            except OSError:
                if attempt == self._io_attempts:
                    raise
                LOGGER.debug(
                    "retrying C4001 I2C write address=0x%02x register=0x%02x attempt=%s",
                    self._address,
                    register,
                    attempt + 1,
                )
                time.sleep(self._io_retry_delay_seconds)

    def _import_smbus(self) -> ModuleType:
        try:
            import smbus

            return smbus
        except ImportError:
            try:
                import smbus2

                return smbus2
            except ImportError as exc:
                msg = "C4001 I2C mode requires smbus or smbus2 on the Raspberry Pi."
                raise RuntimeError(msg) from exc
