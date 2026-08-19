from eleph.app import metadata_for, sensor_type_for
from eleph.config import Settings


def test_c4001_metadata_marks_human_presence_3m_profile() -> None:
    settings = Settings(
        sensor_mode="c4001-i2c",
        c4001_max_range_cm=300,
        c4001_trigger_range_cm=300,
    )

    metadata = metadata_for(settings)

    assert sensor_type_for(settings) == "mmwave_c4001"
    assert metadata["detection_profile"] == "human_presence_3m"
    assert metadata["human_presence_target"] is True
    assert metadata["max_range_cm"] == 300
    assert metadata["trigger_range_cm"] == 300
