import logging

from eleph.config import Settings
from eleph.domain.onboarding import (
    DeviceIdentity,
    ProvisioningPayload,
    ProvisioningResult,
)
from eleph.services.device_config import DeviceConfigStore
from eleph.services.wifi import WifiProvisioner

LOGGER = logging.getLogger(__name__)


class DeviceOnboardingService:
    def __init__(
        self,
        *,
        settings: Settings,
        config_store: DeviceConfigStore,
        wifi_provisioner: WifiProvisioner,
        heartbeat_sender,
    ) -> None:
        self._settings = settings
        self._config_store = config_store
        self._wifi_provisioner = wifi_provisioner
        self._heartbeat_sender = heartbeat_sender

    def provision(
        self,
        payload: ProvisioningPayload,
        *,
        send_heartbeat: bool = True,
    ) -> ProvisioningResult:
        LOGGER.info("starting device provisioning payload=%s", payload.redacted_summary())
        identity = DeviceIdentity.from_payload(payload)
        wifi_result = self._wifi_provisioner.configure(
            ssid=payload.wifi_ssid,
            password=payload.wifi_password,
        )

        if not wifi_result.connected:
            LOGGER.warning(
                "device provisioning could not connect Wi-Fi device_id=%s ssid=%s message=%s",
                payload.device_id,
                payload.wifi_ssid,
                wifi_result.message,
            )
            return ProvisioningResult(
                identity=identity,
                wifi_connected=False,
                heartbeat_sent=False,
                message=wifi_result.message,
            )

        self._config_store.save(identity)
        LOGGER.info(
            "device identity saved path=%s device_id=%s display_name=%s",
            self._config_store.path,
            identity.device_id,
            identity.display_name,
        )

        heartbeat_sent = False
        if send_heartbeat:
            heartbeat_settings = self._settings.with_overrides(device_id=payload.device_id)
            try:
                self._heartbeat_sender(heartbeat_settings, strict_upload=True)
                heartbeat_sent = True
                LOGGER.info("startup heartbeat sent after provisioning device_id=%s", payload.device_id)
            except Exception as exc:
                LOGGER.warning(
                    "startup heartbeat after provisioning failed device_id=%s error=%s",
                    payload.device_id,
                    exc,
                )

        return ProvisioningResult(
            identity=identity,
            wifi_connected=True,
            heartbeat_sent=heartbeat_sent,
            message=wifi_result.message,
        )
