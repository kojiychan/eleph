# Eleph

Eleph is a privacy-first Raspberry Pi motion-monitoring prototype with an iOS companion app. The Raspberry Pi monitor detects activations from a DFRobot Gravity C4001 24GHz mmWave human presence sensor and records one motion event per inactive-to-active transition in Supabase.

This is not fall detection, caregiver notification, or occupancy inference. Those product layers come later.

## Architecture

The project uses a small layered Python package:

- `eleph.cli`: command-line entry point for running and checking the application.
- `eleph.app`: application wiring that connects configuration, logging, sensors, event sinks, and services.
- `eleph.config`: typed runtime settings loaded from environment variables.
- `eleph.domain`: product concepts such as motion events, sensor contracts, and event-sink contracts.
- `eleph.adapters`: hardware and infrastructure adapters, including GPIO, simulator, logging, and Supabase.
- `eleph.services`: orchestration logic for transition detection, debounce, cooldown, and retry behavior.

The monitor does not contain GPIO or Supabase-specific logic. Sensors implement `MotionSensor.is_active()`, and upload destinations implement `MotionEventSink.record_motion()`.

## Repository Layout

```text
.
├── landing/
│   ├── assets/
│   ├── index.html
│   ├── script.js
│   └── styles.css
├── vercel.json
├── package.json
├── pyproject.toml
├── README.md
├── ios/
│   ├── Models/
│   ├── Views/
│   ├── ViewModels/
│   ├── Services/
│   ├── Components/
│   ├── Utilities/
│   ├── Assets.xcassets/
│   └── Package.swift
├── src/
│   └── eleph/
│       ├── __main__.py
│       ├── app.py
│       ├── cli.py
│       ├── config.py
│       ├── logging_config.py
│       ├── adapters/
│       │   ├── events/
│       │   │   ├── logging_sink.py
│       │   │   └── supabase.py
│       │   └── sensors/
│       │       ├── c4001_i2c.py
│       │       ├── infrared_gpio.py
│       │       └── simulated.py
│       ├── domain/
│       │   ├── events.py
│       │   ├── motion.py
│       │   └── sinks.py
│       └── services/
│           ├── motion_monitor.py
│           └── reliable_sink.py
└── tests/
    └── test_motion_monitor.py
```

## Development

Create a virtual environment when you are ready to run tooling:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e ".[dev]"
```

Run the test suite:

```bash
python -m pytest
```

Run the landing page locally:

```bash
npm run dev
```

Build the static landing page for Vercel:

```bash
npm run build
```

Vercel uses `vercel.json` to run the build and serve the generated `dist/` directory.

The beta signup form posts to Supabase from the browser. Configure these Vercel environment
variables with your Supabase project URL and public anon key:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY
```

Apply the `beta_signups` table in `supabase/schema.sql`, or run the standalone helper with a
Supabase Postgres connection string:

```bash
SUPABASE_DB_URL='postgresql://...' python scripts/create_beta_signups_table.py
```

Run the application in simulator mode:

```bash
PYTHONPATH=src python3 -m eleph monitor --sensor simulated --device-id test-device --iterations 5
```

Show the detected configuration:

```bash
PYTHONPATH=src python3 -m eleph doctor
```

## Configuration

Environment variables are used for deployment-friendly configuration:

- `ELEPH_ENV`: deployment environment name. Defaults to `development`.
- `ELEPH_SENSOR_MODE`: sensor adapter to use. Defaults to `simulated`.
- `ELEPH_DEVICE_ID`: stable device identifier included with every event.
- `ELEPH_GPIO_PIN`: BCM GPIO pin for the infrared obstacle sensor digital output.
- `ELEPH_SENSOR_ACTIVE_LOW`: whether the sensor output is active-low. Defaults to `true`.
- `ELEPH_DEBOUNCE_MS`: debounce window for noisy transitions. Defaults to `200`.
- `ELEPH_COOLDOWN_SECONDS`: minimum gap between emitted motion events. Defaults to `2`.
- `ELEPH_POLL_INTERVAL_SECONDS`: polling interval for motion checks. Defaults to `1.0`.
- `ELEPH_EVENT_QUEUE_SIZE`: maximum in-memory retry queue size. Defaults to `100`.
- `ELEPH_LOG_LEVEL`: Python logging level. Defaults to `INFO`.
- `ELEPH_MOTION_EVENT_COOLDOWN_SECONDS`: minimum seconds between inserted `motion_events` rows during continuous motion. Defaults to `180`.
- `ELEPH_MOTION_SESSION_IDLE_TIMEOUT_SECONDS`: seconds without detected motion before an open motion session is ended. Defaults to `180`.
- `ELEPH_C4001_I2C_BUS`: Raspberry Pi I2C bus. Defaults to `1`.
- `ELEPH_C4001_I2C_ADDRESS`: C4001 I2C address. Defaults to `0x2A`.
- `ELEPH_C4001_MIN_RANGE_CM`: C4001 minimum detection range. Defaults to `30`.
- `ELEPH_C4001_MAX_RANGE_CM`: C4001 maximum detection range. Defaults to `300`.
- `ELEPH_C4001_TRIGGER_RANGE_CM`: C4001 trigger range. Defaults to `300`.
- `ELEPH_C4001_TRIGGER_SENSITIVITY`: C4001 trigger sensitivity from `0` to `9`. Defaults to `1`.
- `ELEPH_C4001_KEEP_SENSITIVITY`: C4001 keep sensitivity from `0` to `9`. Defaults to `2`.
- `ELEPH_C4001_TRIGGER_DELAY_MS`: C4001 trigger delay. Defaults to `100`.
- `ELEPH_C4001_KEEP_TIMEOUT_SECONDS`: C4001 keep timeout. Defaults to `2`.
- `ELEPH_C4001_CONFIGURE_ON_START`: whether Eleph writes C4001 range/sensitivity settings on startup. Defaults to `true`.
- `SUPABASE_URL`: Supabase project URL.
- `SUPABASE_KEY`: Supabase credential used by the Raspberry Pi process.
- `SUPABASE_MOTION_TABLE`: table for motion events. Defaults to `motion_events`.
- `SUPABASE_DEVICES_TABLE`: table for device heartbeat status. Defaults to `devices`.
- `ELEPH_HEARTBEAT_INTERVAL_SECONDS`: seconds between online heartbeats. Defaults to `60`.
- `ELEPH_SUPABASE_TIMEOUT_SECONDS`: short HTTP timeout for Supabase calls. Defaults to `3`.

Copy `.env.example` to a local `.env` file if you want a reference, but do not commit `.env` or real credentials.

## Motion Events And Sessions

Eleph keeps `devices.last_motion_at` fresh every time motion is observed, but it throttles `motion_events` so a long bathroom visit does not create hundreds of rows.

```text
first motion after inactivity: update device, start motion session, insert motion_detected
continuous motion under 3 minutes: update device and session, skip motion_detected
continuous motion after 3 minutes: update device and session, insert another motion_detected
no motion for 3 minutes: end the open motion session
```

The app should use `devices.last_motion_at` for life-check recency and `motion_sessions` for bathroom visit history. `motion_events` is now a lower-volume audit/timeline table rather than a row for every sensor poll.

Example payload:

```json
{
  "device_id": "bathroom-monitor-001",
  "event_type": "motion_detected",
  "detected_at": "2026-08-04T17:15:03-07:00",
  "sensor_type": "mmwave_c4001",
  "metadata": {
    "sensor_model": "DFRobot Gravity C4001 24GHz",
    "transport": "i2c",
    "i2c_bus": 1,
    "i2c_address": "0x2a",
    "min_range_cm": 30,
    "max_range_cm": 300,
    "trigger_range_cm": 300
  }
}
```

## Supabase

Expected table:

```sql
-- see supabase/schema.sql
```

Run the SQL in `supabase/schema.sql` from the Supabase SQL editor before testing inserts.

The Raspberry Pi prototype reads `SUPABASE_KEY` from the environment and sends inserts through Supabase REST. For an early trusted-device prototype, this may be an anon key if row-level security allows only the intended insert shape, or a more privileged key kept only on the Pi. A service-role key must never be shipped in a future iOS application. The Supabase client is isolated behind `MotionEventSink` so authentication can be changed later without rewriting sensor or monitor logic.

Failed uploads are logged and retried with bounded exponential backoff through a small in-memory queue. Event timestamps are created when motion is detected, not when a retry eventually succeeds.

## Device Heartbeat

The Pi monitor sends a heartbeat to `public.devices` on startup, every 60 seconds while running, and whenever motion is detected. Heartbeats upsert:

- `device_id`
- `connection_status='online'`
- `last_seen_at`
- `firmware_version`
- `ip_address`, when the Pi can determine it locally

Motion detections also update `devices.last_motion_at` to the motion event timestamp. Supabase has an `after insert` trigger on `motion_events` that mirrors this update, so `last_motion_at` still advances when a motion row is inserted by a retry or future firmware path.

The iOS app should infer status from `last_seen_at`:

- Online: less than 3 minutes old.
- Stale: 3-10 minutes old.
- Offline: more than 10 minutes old or missing.

Send one heartbeat without starting the monitor:

```bash
PYTHONPATH=src python3 -m eleph heartbeat \
  --device-id bathroom-monitor-001 \
  --strict-upload
```

Verify in Supabase:

```sql
select * from public.devices where device_id = 'bathroom-monitor-001';

select *
from public.motion_events
where device_id = 'bathroom-monitor-001'
order by detected_at desc
limit 20;

select *
from public.motion_sessions
where device_id = 'bathroom-monitor-001'
order by started_at desc
limit 20;
```

## C4001 mmWave Sensor

The current prototype target is a DFRobot Gravity C4001 24GHz Human Presence Detection Sensor, 12-meter model, using I2C. DFRobot documents the 12-meter C4001 as a 3.3V/5V sensor with I2C addresses `0x2A`/`0x2B`, UART at 9600 baud, a 100x80 degree beam angle, presence detection up to 8m, and motion/ranging up to 12m.

For Eleph, the default C4001 config intentionally limits the range to 300cm so the bathroom prototype focuses on roughly 2-3 meters instead of the sensor's full room-scale range. The adapter configures C4001 exist/presence mode on startup unless `ELEPH_C4001_CONFIGURE_ON_START=false`.

Supabase events from this mode include `sensor_type=mmwave_c4001` and metadata with `detection_profile=human_presence_3m`, `human_presence_target=true`, `max_range_cm=300`, and `trigger_range_cm=300`. The sensor reports radar presence/motion inside the configured zone; it does not identify a person the way a camera would.

Wire the sensor in I2C mode and set the DIP switch on the back of the sensor to I2C. On a Raspberry Pi, use:

- Sensor `+` to Pi 3.3V or 5V, following your wiring plan.
- Sensor `-` to Pi ground.
- Sensor `C/R` to Pi I2C SCL.
- Sensor `D/T` to Pi I2C SDA.

Run C4001 mode:

```bash
PYTHONPATH=src python3 -m eleph monitor \
  --sensor c4001-i2c \
  --device-id bathroom-monitor-001
```

For a tighter test zone:

```bash
PYTHONPATH=src python3 -m eleph monitor \
  --sensor c4001-i2c \
  --device-id bathroom-monitor-001 \
  --max-range-cm 240 \
  --trigger-range-cm 240
```

The C4001 exist-mode maximum range must be at least 240cm, so use 240cm for the tightest supported setting and 300cm for the normal 2-3m bathroom target.

Simulator mode remains available:

```bash
PYTHONPATH=src python3 -m eleph monitor \
  --sensor simulated \
  --device-id test-device
```

## Raspberry Pi Deployment Notes

The remote Raspberry Pi project directory is:

```text
/home/kojiychan/eleph
```

The repository can be cloned or updated with:

```bash
git clone https://github.com/kojiychan/eleph.git /home/kojiychan/eleph
cd /home/kojiychan/eleph
git pull --ff-only
```

No GPIO settings are changed by the repository setup itself. GPIO is only initialized when the monitor is explicitly run with `--sensor gpio`.

## Raspberry Pi Wi-Fi

Configure the Pi to join the deployment Wi-Fi and keep reconnecting if the link drops:

```bash
cd /home/kojiychan/eleph
chmod +x scripts/configure_wifi.sh scripts/wifi_healthcheck.sh
./scripts/configure_wifi.sh
```

The script prompts for the SSID and password without echoing the password, enables autoconnect, and installs a systemd timer that checks Wi-Fi every minute. To avoid an interactive prompt, run:

```bash
ELEPH_WIFI_SSID='your-network' ELEPH_WIFI_PASSWORD='your-password' ./scripts/configure_wifi.sh
```

Do not commit Wi-Fi passwords. On Raspberry Pi OS with NetworkManager, credentials are stored in root-owned NetworkManager connection files. On older setups, the fallback uses `wpa_passphrase` so the PSK is stored instead of plaintext where supported.

## Synthetic Motion

The Pi can post one synthetic `motion_detected` event when the network comes online, then every 4 hours afterward, so Supabase connectivity is visible even when no one triggers the real sensor. Synthetic events use `sensor_type=simulated` and include metadata:

```json
{
  "synthetic": true,
  "source": "scheduled_fake_motion",
  "interval_hours": 4
}
```

Install the timer on the Pi:

```bash
cd /home/kojiychan/eleph
chmod +x scripts/install_fake_motion_timer.sh
./scripts/install_fake_motion_timer.sh
```

Post one fake event manually:

```bash
PYTHONPATH=src python3 -m eleph post-fake-motion --device-id bathroom-monitor-001
```

## No-Sensor Preflight

Before the C4001 arrives, boot the Pi and run:

```bash
cd /home/kojiychan/eleph
chmod +x scripts/preflight_no_sensor.sh
./scripts/preflight_no_sensor.sh
```

This compiles the Python package, prints configuration, and emits one simulated motion transition. It does not require the C4001 to be connected.

## Sources

- [DFRobot C4001 SEN0610 wiki](https://wiki.dfrobot.com/sen0610/)
- [DFRobot C4001 I2C distance/speed example](https://wiki.dfrobot.com/sen0610/docs/20950)
- [DFRobot C4001 product page](https://www.dfrobot.com/product-2795.html)
