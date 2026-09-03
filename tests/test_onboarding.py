import json
from pathlib import Path

import pytest

from eleph.config import Settings
from eleph.domain.onboarding import ProvisioningError, ProvisioningPayload
from eleph.services.ble_onboarding import (
    DEFAULT_SETUP_DEVICE_NAME,
    ELEPH_PROVISION_COMMAND_UUID,
    ELEPH_SETUP_SERVICE_UUID,
    ELEPH_SETUP_STATUS_UUID,
    BleSetupContract,
    setup_mode_for,
)
from eleph.services.device_config import DeviceConfigStore
from eleph.services.onboarding import DeviceOnboardingService
from eleph.services.wifi import WifiProvisionResult


class RecordingWifiProvisioner:
    def __init__(self, *, connected: bool = True) -> None:
        self.connected = connected
        self.calls: list[tuple[str, str]] = []

    def configure(self, *, ssid: str, password: str) -> WifiProvisionResult:
        self.calls.append((ssid, password))
        return WifiProvisionResult(connected=self.connected, message="recorded")


class RecordingHeartbeat:
    def __init__(self) -> None:
        self.calls: list[Settings] = []

    def __call__(self, settings: Settings, *, strict_upload: bool) -> None:
        self.calls.append(settings)


def test_provisioning_payload_requires_wifi_credentials() -> None:
    with pytest.raises(ProvisioningError):
        ProvisioningPayload.from_mapping(
            {
                "device_id": "bathroom-monitor-001",
                "wifi_ssid": "kenjikojidebbie",
            }
        )


def test_provisioning_saves_identity_without_password_or_claim_token(tmp_path: Path) -> None:
    config_path = tmp_path / "device.json"
    wifi = RecordingWifiProvisioner()
    heartbeat = RecordingHeartbeat()
    service = DeviceOnboardingService(
        settings=Settings(device_config_path=str(config_path)),
        config_store=DeviceConfigStore(config_path),
        wifi_provisioner=wifi,
        heartbeat_sender=heartbeat,
    )
    payload = ProvisioningPayload.from_mapping(
        {
            "device_id": "bathroom-monitor-001",
            "display_name": "Bathroom Monitor",
            "claim_token": "claim-secret",
            "wifi_ssid": "kenjikojidebbie",
            "wifi_password": "wifi-secret",
        }
    )

    result = service.provision(payload)

    assert result.wifi_connected is True
    assert result.heartbeat_sent is True
    assert wifi.calls == [("kenjikojidebbie", "wifi-secret")]
    assert [call.device_id for call in heartbeat.calls] == ["bathroom-monitor-001"]

    stored = json.loads(config_path.read_text(encoding="utf-8"))
    assert stored["device_id"] == "bathroom-monitor-001"
    assert stored["display_name"] == "Bathroom Monitor"
    assert stored["last_wifi_ssid"] == "kenjikojidebbie"
    assert "wifi_password" not in stored
    assert "claim_token" not in stored
    assert "wifi-secret" not in config_path.read_text(encoding="utf-8")
    assert "claim-secret" not in config_path.read_text(encoding="utf-8")


def test_provisioning_does_not_save_identity_if_wifi_fails(tmp_path: Path) -> None:
    config_path = tmp_path / "device.json"
    service = DeviceOnboardingService(
        settings=Settings(device_config_path=str(config_path)),
        config_store=DeviceConfigStore(config_path),
        wifi_provisioner=RecordingWifiProvisioner(connected=False),
        heartbeat_sender=RecordingHeartbeat(),
    )
    payload = ProvisioningPayload.from_mapping(
        {
            "device_id": "bathroom-monitor-001",
            "wifi_ssid": "kenjikojidebbie",
            "wifi_password": "wifi-secret",
        }
    )

    result = service.provision(payload)

    assert result.wifi_connected is False
    assert result.heartbeat_sent is False
    assert not config_path.exists()


def test_settings_loads_device_id_from_local_device_config(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config_path = tmp_path / "device.json"
    config_path.write_text(
        json.dumps(
            {
                "device_id": "bathroom-monitor-001",
                "display_name": "Bathroom Monitor",
                "provisioned_at": "2026-08-26T00:00:00+00:00",
                "last_wifi_ssid": "kenjikojidebbie",
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("ELEPH_DEVICE_CONFIG_PATH", str(config_path))
    monkeypatch.delenv("ELEPH_DEVICE_ID", raising=False)

    settings = Settings.from_env()

    assert settings.device_id == "bathroom-monitor-001"


def test_ble_setup_contract_matches_ios_app() -> None:
    assert BleSetupContract().to_mapping() == {
        "advertised_name": DEFAULT_SETUP_DEVICE_NAME,
        "service_uuid": ELEPH_SETUP_SERVICE_UUID,
        "provision_command_uuid": ELEPH_PROVISION_COMMAND_UUID,
        "setup_status_uuid": ELEPH_SETUP_STATUS_UUID,
    }


def test_ble_setup_mode_enabled_when_device_is_not_provisioned(tmp_path: Path) -> None:
    settings = Settings(device_config_path=str(tmp_path / "missing-device.json"))

    setup_mode = setup_mode_for(settings)

    assert setup_mode.enabled is True
    assert setup_mode.advertised_name == DEFAULT_SETUP_DEVICE_NAME
    assert setup_mode.reason == "device is not provisioned"


def test_ble_setup_mode_enabled_with_device_name_when_supabase_is_missing(tmp_path: Path) -> None:
    config_path = tmp_path / "device.json"
    config_path.write_text(
        json.dumps(
            {
                "device_id": "bathroom-monitor-001",
                "display_name": "Grandma's Bathroom",
                "provisioned_at": "2026-08-26T00:00:00+00:00",
                "last_wifi_ssid": "kenjikojidebbie",
            }
        ),
        encoding="utf-8",
    )
    settings = Settings(device_config_path=str(config_path))

    setup_mode = setup_mode_for(settings)

    assert setup_mode.enabled is True
    assert setup_mode.advertised_name == "Grandma's Bathroom"
    assert setup_mode.reason == "Supabase configuration is missing"


def test_ble_setup_mode_disabled_when_supabase_is_reachable(tmp_path: Path) -> None:
    config_path = tmp_path / "device.json"
    config_path.write_text(
        json.dumps(
            {
                "device_id": "bathroom-monitor-001",
                "display_name": "Grandma's Bathroom",
                "provisioned_at": "2026-08-26T00:00:00+00:00",
                "last_wifi_ssid": "kenjikojidebbie",
            }
        ),
        encoding="utf-8",
    )
    settings = Settings(
        device_config_path=str(config_path),
        supabase_url="https://example.supabase.co",
        supabase_key="anon-key",
    )

    setup_mode = setup_mode_for(settings, supabase_reachable=True)

    assert setup_mode.enabled is False
    assert setup_mode.advertised_name == "Grandma's Bathroom"
    assert setup_mode.reason == "device is provisioned and Supabase is reachable"
