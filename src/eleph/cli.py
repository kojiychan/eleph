import argparse
import logging
import signal
from threading import Event
from collections.abc import Sequence

from eleph.app import build_motion_monitor, post_fake_motion
from eleph.config import Settings, parse_bool

LOGGER = logging.getLogger(__name__)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="eleph")
    subparsers = parser.add_subparsers(dest="command", required=True)

    monitor_parser = subparsers.add_parser("monitor", help="Run the motion monitor.")
    _add_monitor_arguments(monitor_parser)

    run_parser = subparsers.add_parser("run", help="Alias for monitor.")
    _add_monitor_arguments(run_parser)

    fake_motion_parser = subparsers.add_parser(
        "post-fake-motion",
        help="Post one synthetic motion event for connectivity testing.",
    )
    fake_motion_parser.add_argument("--device-id", default=None, help="Stable device identifier.")
    fake_motion_parser.add_argument(
        "--strict-upload",
        action="store_true",
        help="Fail if the Supabase upload fails instead of falling back to local logging.",
    )

    subparsers.add_parser("doctor", help="Print runtime configuration.")
    return parser


def _add_monitor_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--sensor",
        choices=["simulated", "gpio", "c4001-i2c"],
        default=None,
        help="Sensor adapter to use.",
    )
    parser.add_argument("--pin", type=int, default=None, help="BCM GPIO input pin.")
    parser.add_argument("--device-id", default=None, help="Stable device identifier.")
    parser.add_argument(
        "--active-low",
        type=parse_bool,
        default=None,
        help="Whether the sensor output is active-low.",
    )
    parser.add_argument("--debounce-ms", type=int, default=None)
    parser.add_argument("--cooldown-seconds", type=float, default=None)
    parser.add_argument("--poll-interval-seconds", type=float, default=None)
    parser.add_argument(
        "--max-range-cm",
        type=int,
        default=None,
        help="C4001 maximum presence range in centimeters. Defaults to 300cm.",
    )
    parser.add_argument(
        "--trigger-range-cm",
        type=int,
        default=None,
        help="C4001 trigger range in centimeters. Defaults to the max range.",
    )
    parser.add_argument(
        "--iterations",
        type=int,
        default=None,
        help="Stop after this many polling iterations. Defaults to running forever.",
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    settings = Settings.from_env()

    if args.command == "doctor":
        print(settings.format_summary())
        return 0

    if args.command in {"monitor", "run"}:
        settings = settings.with_overrides(
            sensor_mode=args.sensor,
            device_id=args.device_id,
            gpio_pin=args.pin,
            sensor_active_low=args.active_low,
            debounce_ms=args.debounce_ms,
            cooldown_seconds=args.cooldown_seconds,
            poll_interval_seconds=args.poll_interval_seconds,
            c4001_max_range_cm=args.max_range_cm,
            c4001_trigger_range_cm=args.trigger_range_cm,
        )
        stop_event = _shutdown_event()
        with build_motion_monitor(settings) as monitor:
            for event in monitor.watch(iterations=args.iterations, stop_event=stop_event):
                LOGGER.info("motion event emitted payload=%s", event.to_supabase_payload())
        return 0

    if args.command == "post-fake-motion":
        settings = settings.with_overrides(device_id=args.device_id)
        event = post_fake_motion(settings, strict_upload=args.strict_upload)
        LOGGER.info("fake motion event emitted payload=%s", event.to_supabase_payload())
        return 0

    parser.error(f"Unhandled command: {args.command}")
    return 2


def _shutdown_event() -> Event:
    stop_event = Event()

    def request_stop(signum: int, frame: object) -> None:
        LOGGER.info("shutdown requested signal=%s", signum)
        stop_event.set()

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)
    return stop_event
