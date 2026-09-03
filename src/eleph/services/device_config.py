import json
from pathlib import Path

from eleph.domain.onboarding import DeviceIdentity


class DeviceConfigStore:
    def __init__(self, path: Path) -> None:
        self._path = path

    @classmethod
    def from_settings(cls, settings) -> "DeviceConfigStore":
        return cls(Path(settings.device_config_path))

    @property
    def path(self) -> Path:
        return self._path

    def exists(self) -> bool:
        return self._path.exists()

    def load(self) -> DeviceIdentity | None:
        if not self._path.exists():
            return None

        data = json.loads(self._path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            msg = f"Device config at {self._path} must contain a JSON object."
            raise ValueError(msg)
        return DeviceIdentity.from_mapping(data)

    def save(self, identity: DeviceIdentity) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._path.write_text(
            json.dumps(identity.to_mapping(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        self._path.chmod(0o600)
