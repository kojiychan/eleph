from types import ModuleType


class InfraredGpioSensor:
    """Digital infrared obstacle sensor backed by a Raspberry Pi GPIO input."""

    def __init__(self, *, pin: int, active_low: bool) -> None:
        self._pin = pin
        self._active_low = active_low
        self._gpio: ModuleType | None = None

    def __enter__(self) -> "InfraredGpioSensor":
        try:
            import RPi.GPIO as GPIO
        except ImportError as exc:
            msg = "RPi.GPIO is required for --sensor gpio on Raspberry Pi."
            raise RuntimeError(msg) from exc

        self._gpio = GPIO
        GPIO.setmode(GPIO.BCM)
        GPIO.setup(self._pin, GPIO.IN)
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        if self._gpio is not None:
            self._gpio.cleanup(self._pin)

    def is_active(self) -> bool:
        if self._gpio is None:
            msg = "GPIO sensor must be used as a context manager before reading."
            raise RuntimeError(msg)

        raw_high = self._gpio.input(self._pin) == self._gpio.HIGH
        return not raw_high if self._active_low else raw_high
