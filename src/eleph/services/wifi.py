from dataclasses import dataclass
import logging
import subprocess
from typing import Protocol

LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class WifiProvisionResult:
    connected: bool
    message: str


class WifiProvisioner(Protocol):
    def configure(self, *, ssid: str, password: str) -> WifiProvisionResult:
        ...


class DryRunWifiProvisioner:
    def configure(self, *, ssid: str, password: str) -> WifiProvisionResult:
        LOGGER.info("dry-run Wi-Fi provisioning accepted ssid=%s", ssid)
        return WifiProvisionResult(connected=True, message="dry-run Wi-Fi provisioning")


class NmcliWifiProvisioner:
    def __init__(
        self,
        *,
        iface: str = "wlan0",
        timeout_seconds: float = 35.0,
        use_sudo: bool = False,
    ) -> None:
        self._iface = iface
        self._timeout_seconds = timeout_seconds
        self._use_sudo = use_sudo

    def configure(self, *, ssid: str, password: str) -> WifiProvisionResult:
        LOGGER.info("configuring Wi-Fi via nmcli ssid=%s iface=%s", ssid, self._iface)
        prefix = ["sudo"] if self._use_sudo else []
        commands = [
            [*prefix, "nmcli", "radio", "wifi", "on"],
            [
                *prefix,
                "nmcli",
                "--wait",
                "30",
                "device",
                "wifi",
                "connect",
                ssid,
                "password",
                password,
                "ifname",
                self._iface,
            ],
            [
                *prefix,
                "nmcli",
                "connection",
                "modify",
                ssid,
                "connection.autoconnect",
                "yes",
            ],
            [
                *prefix,
                "nmcli",
                "connection",
                "modify",
                ssid,
                "connection.autoconnect-priority",
                "100",
            ],
        ]

        for command in commands:
            try:
                subprocess.run(
                    command,
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=self._timeout_seconds,
                )
            except FileNotFoundError:
                return WifiProvisionResult(
                    connected=False,
                    message="nmcli is not installed on this Raspberry Pi image",
                )
            except subprocess.CalledProcessError as exc:
                LOGGER.warning(
                    "Wi-Fi provisioning command failed command=%s status=%s stderr=%s",
                    _redact_command(command),
                    exc.returncode,
                    _redact_password(exc.stderr, password),
                )
                return WifiProvisionResult(
                    connected=False,
                    message=f"nmcli failed while connecting to {ssid}",
                )
            except subprocess.TimeoutExpired:
                LOGGER.warning("Wi-Fi provisioning timed out command=%s", _redact_command(command))
                return WifiProvisionResult(
                    connected=False,
                    message=f"nmcli timed out while connecting to {ssid}",
                )

        return WifiProvisionResult(connected=True, message=f"connected to {ssid}")


def _redact_command(command: list[str]) -> list[str]:
    redacted = list(command)
    for index, value in enumerate(redacted[:-1]):
        if value == "password":
            redacted[index + 1] = "[redacted]"
    return redacted


def _redact_password(value: str | None, password: str) -> str:
    if value is None:
        return ""
    return value.replace(password, "[redacted]")
