from datetime import datetime
from typing import Protocol


class DeviceStatusReporter(Protocol):
    def report_online(self, *, last_motion_at: datetime | None = None) -> None:
        ...

    def maybe_report_online(self) -> None:
        ...
