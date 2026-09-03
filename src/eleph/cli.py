import argparse
import json
import logging
from pathlib import Path
import signal
from threading import Event
from collections.abc import Sequence

from eleph.app import build_motion_monitor, post_device_heartbeat, post_fake_motion, provision_device
from eleph.config import Settings, parse_bool
from eleph.domain.onboarding import ProvisioningPayload
from eleph.services.ble_onboarding import BleOnboardingServer, BleSetupContract, setup_mode_for

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

    heartbeat_parser = subparsers.add_parser(
        "heartbeat",
        help="Post one device heartbeat for connectivity testing.",
    )
    heartbeat_parser.add_argument("--device-id", default=None, help="Stable device identifier.")
    heartbeat_parser.add_argument(
        "--strict-upload",
        action="store_true",
        help="Fail if the Supabase heartbeat fails instead of logging and continuing.",
    )

    provision_parser = subparsers.add_parser(
        "provision",
        help="Provision identity and Wi-Fi from an app-style onboarding payload.",
    )
    payload_group = provision_parser.add_mutually_exclusive_group(required=True)
    payload_group.add_argument("--payload-json", help="Provisioning payload as JSON.")
    payload_group.add_argument(
        "--payload-file",
        type=Path,
        help="Path to a JSON file containing the provisioning payload.",
    )
    provision_parser.add_argument(
        "--dry-run-wifi",
        action="store_true",
        help="Validate and save config without changing the Pi Wi-Fi.",
    )
    provision_parser.add_argument(
        "--skip-heartbeat",
        action="store_true",
        help="Skip the post-provisioning Supabase heartbeat.",
    )

    subparsers.add_parser(
        "setup-server",
        help="Run the BLE setup GATT server when the Pi needs onboarding.",
    )
    setup_server_parser = subparsers.choices["setup-server"]
    setup_server_parser.add_argument(
        "--print-only",
        action="store_true",
        help="Print the BLE contract and setup mode without starting BlueZ.",
    )
    setup_server_parser.add_argument(
        "--force",
        action="store_true",
        help="Start BLE advertising even if the device appears provisioned.",
    )
    setup_server_parser.add_argument(
        "--dry-run-wifi",
        action="store_true",
        help="Accept provisioning payloads without changing the Pi Wi-Fi.",
    )
    setup_server_parser.add_argument(
        "--skip-heartbeat",
        action="store_true",
        help="Skip the post-provisioning Supabase heartbeat.",
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

    if args.command == "heartbeat":
        settings = settings.with_overrides(device_id=args.device_id)
        post_device_heartbeat(settings, strict_upload=args.strict_upload)
        LOGGER.info("device heartbeat emitted device_id=%s", settings.device_id)
        return 0

    if args.command == "provision":
        payload = _load_provisioning_payload(args)
        result = provision_device(
            settings,
            payload,
            dry_run_wifi=args.dry_run_wifi,
            send_heartbeat=not args.skip_heartbeat,
        )
        print(
            json.dumps(
                {
                    "device_id": result.identity.device_id,
                    "display_name": result.identity.display_name,
                    "wifi_connected": result.wifi_connected,
                    "heartbeat_sent": result.heartbeat_sent,
                    "message": result.message,
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 0 if result.wifi_connected else 1

    if args.command == "setup-server":
        setup_mode = setup_mode_for(settings)
        contract = BleSetupContract(advertised_name=setup_mode.advertised_name)
        server = BleOnboardingServer(
            contract=contract,
            setup_mode=setup_mode,
            on_payload=lambda payload: provision_device(
                settings,
                payload,
                dry_run_wifi=args.dry_run_wifi,
                send_heartbeat=not args.skip_heartbeat,
            ),
        )
        print(
            json.dumps(
                {
                    "contract": server.contract.to_mapping(),
                    "setup_mode": {
                        "enabled": setup_mode.enabled,
                        "advertised_name": setup_mode.advertised_name,
                        "reason": setup_mode.reason,
                    },
                },
                indent=2,
                sort_keys=True,
            )
        )
        if setup_mode.enabled:
            LOGGER.warning("BLE setup mode should run: %s", setup_mode.reason)
        else:
            LOGGER.info("BLE setup mode not needed: %s", setup_mode.reason)
        if args.print_only:
            return 0
        if not setup_mode.enabled and not args.force:
            LOGGER.info("Use --force to advertise BLE setup anyway.")
            return 0
        server.run()
        return 0

    parser.error(f"Unhandled command: {args.command}")
    return 2


def _load_provisioning_payload(args: argparse.Namespace) -> ProvisioningPayload:
    if args.payload_json:
        data = json.loads(args.payload_json)
    else:
        data = json.loads(args.payload_file.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        msg = "Provisioning payload must be a JSON object."
        raise ValueError(msg)
    return ProvisioningPayload.from_mapping(data)


def _shutdown_event() -> Event:
    stop_event = Event()

    def request_stop(signum: int, frame: object) -> None:
        LOGGER.info("shutdown requested signal=%s", signum)
        stop_event.set()

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)
    return stop_event
