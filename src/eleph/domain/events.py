from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any


@dataclass(frozen=True)
class MotionEvent:
    device_id: str
    event_type: str
    detected_at: datetime
    sensor_type: str = "infrared_obstacle"
    metadata: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def detected_now(
        cls,
        *,
        device_id: str,
        sensor_type: str = "infrared_obstacle",
        metadata: dict[str, Any] | None = None,
    ) -> "MotionEvent":
        return cls(
            device_id=device_id,
            event_type="motion_detected",
            detected_at=datetime.now(tz=UTC),
            sensor_type=sensor_type,
            metadata=metadata or {},
        )

    def to_supabase_payload(self) -> dict[str, Any]:
        return {
            "device_id": self.device_id,
            "event_type": self.event_type,
            "detected_at": self.detected_at.isoformat(),
            "sensor_type": self.sensor_type,
            "metadata": self.metadata,
        }
