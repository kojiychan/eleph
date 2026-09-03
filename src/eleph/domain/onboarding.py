from dataclasses import dataclass
from datetime import UTC, datetime


class ProvisioningError(ValueError):
    pass


@dataclass(frozen=True)
class ProvisioningPayload:
    device_id: str
    wifi_ssid: str
    wifi_password: str
    display_name: str = "Bathroom Monitor"
    claim_token: str | None = None

    @classmethod
    def from_mapping(cls, data: dict[str, object]) -> "ProvisioningPayload":
        device_id = _required_string(data, "device_id")
        wifi_ssid = _required_string(data, "wifi_ssid")
        wifi_password = _required_string(data, "wifi_password")
        display_name = _optional_string(data, "display_name") or cls.display_name
        claim_token = _optional_string(data, "claim_token")
        return cls(
            device_id=device_id,
            display_name=display_name,
            claim_token=claim_token,
            wifi_ssid=wifi_ssid,
            wifi_password=wifi_password,
        )

    def redacted_summary(self) -> dict[str, object]:
        return {
            "device_id": self.device_id,
            "display_name": self.display_name,
            "claim_token_configured": self.claim_token is not None,
            "wifi_ssid": self.wifi_ssid,
            "wifi_password_configured": bool(self.wifi_password),
        }


@dataclass(frozen=True)
class DeviceIdentity:
    device_id: str
    display_name: str
    provisioned_at: datetime
    last_wifi_ssid: str | None = None

    @classmethod
    def from_payload(cls, payload: ProvisioningPayload) -> "DeviceIdentity":
        return cls(
            device_id=payload.device_id,
            display_name=payload.display_name,
            provisioned_at=datetime.now(tz=UTC),
            last_wifi_ssid=payload.wifi_ssid,
        )

    @classmethod
    def from_mapping(cls, data: dict[str, object]) -> "DeviceIdentity":
        provisioned_at_raw = _required_string(data, "provisioned_at")
        provisioned_at = datetime.fromisoformat(provisioned_at_raw)
        if provisioned_at.tzinfo is None:
            provisioned_at = provisioned_at.replace(tzinfo=UTC)
        return cls(
            device_id=_required_string(data, "device_id"),
            display_name=_required_string(data, "display_name"),
            provisioned_at=provisioned_at,
            last_wifi_ssid=_optional_string(data, "last_wifi_ssid"),
        )

    def to_mapping(self) -> dict[str, object]:
        return {
            "device_id": self.device_id,
            "display_name": self.display_name,
            "provisioned_at": self.provisioned_at.astimezone(UTC).isoformat(),
            "last_wifi_ssid": self.last_wifi_ssid,
        }


@dataclass(frozen=True)
class ProvisioningResult:
    identity: DeviceIdentity
    wifi_connected: bool
    heartbeat_sent: bool
    message: str


def _required_string(data: dict[str, object], key: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ProvisioningError(f"Provisioning payload requires non-empty {key}.")
    return value.strip()


def _optional_string(data: dict[str, object], key: str) -> str | None:
    value = data.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        raise ProvisioningError(f"Provisioning payload field {key} must be a string.")
    normalized = value.strip()
    return normalized or None
