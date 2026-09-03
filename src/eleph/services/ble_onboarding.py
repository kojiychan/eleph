from collections.abc import Awaitable, Callable
import asyncio
from dataclasses import dataclass
import inspect
import json
import logging
import signal
from typing import Any

from eleph.config import Settings
from eleph.domain.onboarding import ProvisioningPayload, ProvisioningResult
from eleph.services.device_config import DeviceConfigStore


LOGGER = logging.getLogger(__name__)

ELEPH_SETUP_SERVICE_UUID = "E1E10001-4B18-4F7D-9D25-000000000001"
ELEPH_SETUP_STATUS_UUID = "E1E10002-4B18-4F7D-9D25-000000000001"
ELEPH_PROVISION_COMMAND_UUID = "E1E10003-4B18-4F7D-9D25-000000000001"
DEFAULT_SETUP_DEVICE_NAME = "Eleph Setup"
BLUEZ_SERVICE_NAME = "org.bluez"
APP_PATH = "/com/eleph/setup"
SERVICE_PATH = f"{APP_PATH}/service0"
STATUS_CHARACTERISTIC_PATH = f"{SERVICE_PATH}/char0"
PROVISION_CHARACTERISTIC_PATH = f"{SERVICE_PATH}/char1"
ADVERTISEMENT_PATH = "/com/eleph/setup/advertisement0"
MAX_PROVISIONING_PAYLOAD_BYTES = 64 * 1024

ProvisioningHandler = Callable[[ProvisioningPayload], ProvisioningResult | Awaitable[ProvisioningResult]]


@dataclass(frozen=True)
class BleSetupContract:
    service_uuid: str = ELEPH_SETUP_SERVICE_UUID
    provision_command_uuid: str = ELEPH_PROVISION_COMMAND_UUID
    setup_status_uuid: str = ELEPH_SETUP_STATUS_UUID
    advertised_name: str = DEFAULT_SETUP_DEVICE_NAME

    def to_mapping(self) -> dict[str, str]:
        return {
            "advertised_name": self.advertised_name,
            "service_uuid": self.service_uuid,
            "provision_command_uuid": self.provision_command_uuid,
            "setup_status_uuid": self.setup_status_uuid,
        }


@dataclass(frozen=True)
class BleSetupMode:
    enabled: bool
    advertised_name: str
    reason: str


def setup_mode_for(
    settings: Settings,
    *,
    config_store: DeviceConfigStore | None = None,
    supabase_reachable: bool | None = None,
) -> BleSetupMode:
    store = config_store or DeviceConfigStore.from_settings(settings)
    identity = store.load()
    advertised_name = identity.display_name if identity else DEFAULT_SETUP_DEVICE_NAME

    if identity is None:
        return BleSetupMode(
            enabled=True,
            advertised_name=DEFAULT_SETUP_DEVICE_NAME,
            reason="device is not provisioned",
        )

    if not settings.supabase_enabled:
        return BleSetupMode(
            enabled=True,
            advertised_name=advertised_name,
            reason="Supabase configuration is missing",
        )

    if supabase_reachable is False:
        return BleSetupMode(
            enabled=True,
            advertised_name=advertised_name,
            reason="Supabase is unreachable",
        )

    return BleSetupMode(
        enabled=False,
        advertised_name=advertised_name,
        reason="device is provisioned and Supabase is reachable",
    )


class BleOnboardingServer:
    def __init__(
        self,
        *,
        contract: BleSetupContract | None = None,
        setup_mode: BleSetupMode | None = None,
        on_payload: ProvisioningHandler | None = None,
    ) -> None:
        self._contract = contract or BleSetupContract()
        self._setup_mode = setup_mode
        self._on_payload = on_payload

    @property
    def contract(self) -> BleSetupContract:
        return self._contract

    @property
    def setup_mode(self) -> BleSetupMode | None:
        return self._setup_mode

    def run(self) -> None:
        asyncio.run(self.run_async())

    async def run_async(self) -> None:
        bluez = _load_dbus_next()
        bus = await bluez.MessageBus(bus_type=bluez.BusType.SYSTEM).connect()
        adapter_path = await _find_bluez_adapter_path(bus)

        state = _ProvisioningState(
            initial_status=_initial_status_for(self._setup_mode),
            on_payload=self._handle_payload,
        )
        app = _GattApplication(state=state, contract=self._contract, bluez=bluez)
        advertisement = _Advertisement(contract=self._contract, bluez=bluez)

        for path, interface in app.exported_interfaces:
            bus.export(path, interface)
        bus.export(ADVERTISEMENT_PATH, advertisement)

        adapter_object = await _proxy_object(bus, adapter_path, bluez)
        gatt_manager = adapter_object.get_interface("org.bluez.GattManager1")
        advertising_manager = adapter_object.get_interface("org.bluez.LEAdvertisingManager1")

        await gatt_manager.call_register_application(APP_PATH, {})
        await advertising_manager.call_register_advertisement(ADVERTISEMENT_PATH, {})
        LOGGER.info(
            "BLE setup server advertising name=%s service_uuid=%s adapter=%s",
            self._contract.advertised_name,
            self._contract.service_uuid,
            adapter_path,
        )

        stop_event = asyncio.Event()
        loop = asyncio.get_running_loop()
        for signame in ("SIGINT", "SIGTERM"):
            try:
                loop.add_signal_handler(getattr(signal, signame), stop_event.set)
            except (NotImplementedError, RuntimeError, AttributeError):
                pass

        try:
            await stop_event.wait()
        finally:
            LOGGER.info("stopping BLE setup server")
            try:
                await advertising_manager.call_unregister_advertisement(ADVERTISEMENT_PATH)
            except Exception as exc:
                LOGGER.debug("failed to unregister BLE advertisement: %s", exc)
            try:
                await gatt_manager.call_unregister_application(APP_PATH)
            except Exception as exc:
                LOGGER.debug("failed to unregister BLE GATT application: %s", exc)
            bus.disconnect()

    async def _handle_payload(self, payload: ProvisioningPayload) -> ProvisioningResult:
        if self._on_payload is None:
            msg = "No provisioning handler configured for BLE setup server."
            raise RuntimeError(msg)

        result = self._on_payload(payload)
        if inspect.isawaitable(result):
            return await result
        return result


def _initial_status_for(setup_mode: BleSetupMode | None) -> str:
    if setup_mode is not None and not setup_mode.enabled:
        return "alreadyProvisioned"
    return "readyForProvisioning"


def _load_dbus_next():
    try:
        from dbus_next import BusType, Variant
        from dbus_next.aio import MessageBus
        from dbus_next.service import ServiceInterface, dbus_property, method
    except ImportError as exc:
        msg = (
            "BLE setup requires dbus-next and BlueZ on the Raspberry Pi. "
            "Install with `python3 -m pip install dbus-next` or install the Eleph package "
            "dependencies, then run `python3 -m eleph setup-server` on the Pi."
        )
        raise RuntimeError(msg) from exc

    class BluezModule:
        pass

    bluez = BluezModule()
    bluez.BusType = BusType
    bluez.MessageBus = MessageBus
    bluez.ServiceInterface = ServiceInterface
    bluez.Variant = Variant
    bluez.dbus_property = dbus_property
    bluez.method = method
    return bluez


async def _find_bluez_adapter_path(bus) -> str:
    bluez = _load_dbus_next()
    root = await _proxy_object(bus, "/", bluez)
    object_manager = root.get_interface("org.freedesktop.DBus.ObjectManager")
    managed_objects = await object_manager.call_get_managed_objects()
    for path, interfaces in managed_objects.items():
        if "org.bluez.GattManager1" in interfaces and "org.bluez.LEAdvertisingManager1" in interfaces:
            return path
    msg = (
        "No BlueZ adapter with GATT and LE advertising support was found. "
        "Make sure Bluetooth is enabled on the Raspberry Pi and bluetoothd is running."
    )
    raise RuntimeError(msg)


async def _proxy_object(bus, path: str, bluez):
    introspection = await bus.introspect(BLUEZ_SERVICE_NAME, path)
    return bus.get_proxy_object(BLUEZ_SERVICE_NAME, path, introspection)


class _ProvisioningState:
    def __init__(
        self,
        *,
        initial_status: str,
        on_payload: Callable[[ProvisioningPayload], Awaitable[ProvisioningResult]],
    ) -> None:
        self._status = initial_status
        self._status_characteristic = None
        self._provision_buffer = bytearray()
        self._on_payload = on_payload
        self._lock = asyncio.Lock()

    @property
    def status(self) -> str:
        return self._status

    @property
    def value(self) -> list[int]:
        return list(self._status.encode("utf-8"))

    def attach_status_characteristic(self, characteristic) -> None:
        self._status_characteristic = characteristic

    def set_status(self, status: str) -> None:
        if self._status == status:
            return
        self._status = status
        LOGGER.info("BLE provisioning status=%s", status)
        if self._status_characteristic is not None:
            self._status_characteristic.notify_status_changed()

    async def accept_chunk(self, chunk: bytes) -> None:
        async with self._lock:
            self.set_status("receivingPayload")
            self._provision_buffer.extend(chunk)

            if len(self._provision_buffer) > MAX_PROVISIONING_PAYLOAD_BYTES:
                self._provision_buffer.clear()
                self.set_status("failed")
                msg = "BLE provisioning payload is too large."
                raise ValueError(msg)

            if b"\n" not in self._provision_buffer:
                return

            payload_bytes, _, remainder = self._provision_buffer.partition(b"\n")
            self._provision_buffer = bytearray(remainder)
            await self._process_payload(payload_bytes)

    async def _process_payload(self, payload_bytes: bytes) -> None:
        try:
            raw_payload = payload_bytes.decode("utf-8")
            data = json.loads(raw_payload)
            if not isinstance(data, dict):
                msg = "BLE provisioning payload must be a JSON object."
                raise ValueError(msg)
            payload = ProvisioningPayload.from_mapping(data)
            self.set_status("connectingToWiFi")
            result = await self._on_payload(payload)
        except Exception:
            LOGGER.exception("BLE provisioning failed")
            self.set_status("failed")
            raise

        if result.wifi_connected:
            self.set_status("connectedToWiFi")
            if result.heartbeat_sent:
                self.set_status("online")
            return
        self.set_status("failed")


class _GattApplication:
    def __init__(self, *, state: _ProvisioningState, contract: BleSetupContract, bluez) -> None:
        self._object_manager = _ObjectManager(bluez)
        self._service = _SetupService(contract=contract, bluez=bluez)
        self._status = _StatusCharacteristic(state=state, contract=contract, bluez=bluez)
        self._provision = _ProvisionCharacteristic(state=state, contract=contract, bluez=bluez)
        state.attach_status_characteristic(self._status)

        self.exported_interfaces = [
            (APP_PATH, self._object_manager),
            (SERVICE_PATH, self._service),
            (STATUS_CHARACTERISTIC_PATH, self._status),
            (PROVISION_CHARACTERISTIC_PATH, self._provision),
        ]
        self._object_manager.set_managed_objects(
            {
                SERVICE_PATH: {
                    "org.bluez.GattService1": {
                        "UUID": bluez.Variant("s", contract.service_uuid),
                        "Primary": bluez.Variant("b", True),
                    }
                },
                STATUS_CHARACTERISTIC_PATH: {
                    "org.bluez.GattCharacteristic1": {
                        "UUID": bluez.Variant("s", contract.setup_status_uuid),
                        "Service": bluez.Variant("o", SERVICE_PATH),
                        "Flags": bluez.Variant("as", ["read", "notify"]),
                    }
                },
                PROVISION_CHARACTERISTIC_PATH: {
                    "org.bluez.GattCharacteristic1": {
                        "UUID": bluez.Variant("s", contract.provision_command_uuid),
                        "Service": bluez.Variant("o", SERVICE_PATH),
                        "Flags": bluez.Variant("as", ["write", "write-without-response"]),
                    }
                },
            }
        )


def _ObjectManager(bluez):
    class ObjectManager(bluez.ServiceInterface):
        def __init__(self) -> None:
            super().__init__("org.freedesktop.DBus.ObjectManager")
            self._managed_objects: dict[str, dict[str, dict[str, Any]]] = {}

        def set_managed_objects(self, managed_objects: dict[str, dict[str, dict[str, Any]]]) -> None:
            self._managed_objects = managed_objects

        @bluez.method()
        def GetManagedObjects(self) -> "a{oa{sa{sv}}}":
            return self._managed_objects

    return ObjectManager()


def _SetupService(*, contract: BleSetupContract, bluez):
    class SetupService(bluez.ServiceInterface):
        def __init__(self) -> None:
            super().__init__("org.bluez.GattService1")

        @bluez.dbus_property()
        def UUID(self) -> "s":
            return contract.service_uuid

        @bluez.dbus_property()
        def Primary(self) -> "b":
            return True

        @bluez.dbus_property()
        def Characteristics(self) -> "ao":
            return [STATUS_CHARACTERISTIC_PATH, PROVISION_CHARACTERISTIC_PATH]

    return SetupService()


def _StatusCharacteristic(*, state: _ProvisioningState, contract: BleSetupContract, bluez):
    class StatusCharacteristic(bluez.ServiceInterface):
        def __init__(self) -> None:
            super().__init__("org.bluez.GattCharacteristic1")
            self._notifying = False

        @bluez.dbus_property()
        def UUID(self) -> "s":
            return contract.setup_status_uuid

        @bluez.dbus_property()
        def Service(self) -> "o":
            return SERVICE_PATH

        @bluez.dbus_property()
        def Flags(self) -> "as":
            return ["read", "notify"]

        @bluez.dbus_property()
        def Value(self) -> "ay":
            return state.value

        @bluez.method()
        def ReadValue(self, options: "a{sv}") -> "ay":
            return state.value

        @bluez.method()
        def StartNotify(self) -> None:
            self._notifying = True
            self.notify_status_changed()

        @bluez.method()
        def StopNotify(self) -> None:
            self._notifying = False

        def notify_status_changed(self) -> None:
            if self._notifying:
                self.emit_properties_changed({"Value": state.value})

    return StatusCharacteristic()


def _ProvisionCharacteristic(*, state: _ProvisioningState, contract: BleSetupContract, bluez):
    class ProvisionCharacteristic(bluez.ServiceInterface):
        def __init__(self) -> None:
            super().__init__("org.bluez.GattCharacteristic1")

        @bluez.dbus_property()
        def UUID(self) -> "s":
            return contract.provision_command_uuid

        @bluez.dbus_property()
        def Service(self) -> "o":
            return SERVICE_PATH

        @bluez.dbus_property()
        def Flags(self) -> "as":
            return ["write", "write-without-response"]

        @bluez.method()
        async def WriteValue(self, value: "ay", options: "a{sv}") -> None:
            await state.accept_chunk(bytes(value))

    return ProvisionCharacteristic()


def _Advertisement(*, contract: BleSetupContract, bluez):
    class Advertisement(bluez.ServiceInterface):
        def __init__(self) -> None:
            super().__init__("org.bluez.LEAdvertisement1")

        @bluez.dbus_property()
        def Type(self) -> "s":
            return "peripheral"

        @bluez.dbus_property()
        def ServiceUUIDs(self) -> "as":
            return [contract.service_uuid]

        @bluez.dbus_property()
        def LocalName(self) -> "s":
            return contract.advertised_name

        @bluez.dbus_property()
        def Includes(self) -> "as":
            return ["tx-power"]

        @bluez.method()
        def Release(self) -> None:
            LOGGER.info("BLE setup advertisement released by BlueZ")

    return Advertisement()
