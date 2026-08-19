# Eleph iOS

SwiftUI iOS 17+ companion app for the Eleph bathroom monitor. This frontend helps a caregiver quickly answer: "Do I need to check on my loved one?"

## Current Status

The app can read real Supabase motion data when configured, and falls back to realistic mock data when no local Supabase configuration exists.

- No production Bluetooth or Wi-Fi provisioning is implemented.
- No production authentication or notifications are implemented.
- No Supabase credentials are hardcoded or required.

## Architecture

The app uses SwiftUI with MVVM-style view models and async/await-ready service protocols.

- `Models/`: `MonitorDevice`, `MotionEvent`, `AlertEvent`, `AlertPreferences`, `NighttimeSchedule`, `UserProfile`, `CaregiverContact`, and `DailyActivitySummary`.
- `Views/`: onboarding, Home, Activity, Settings, and tab navigation.
- `ViewModels/`: screen state and user actions.
- `Services/`: repository and integration protocols plus Supabase and mock implementations.
- `Components/`: reusable cards, banners, timeline, metric cards, threshold picker, empty/loading/error states, and onboarding progress.
- `Utilities/`: formatting helpers, colors, loadable state, and preview scenarios.

## Navigation

The main app has three bottom tabs in this order:

1. Home
2. Activity
3. Settings

Home is the default tab and surfaces connection status, wellness status, inactivity progress, daily summary, and recent motion.

## Onboarding Flow

The first-run onboarding is state-driven and includes:

1. Welcome
2. Choose `New User` or `Sign In`

Existing users enter email and password, then continue to the dashboard.

New monitor setup includes:

1. Plug in and place the monitor
2. Bluetooth setup
3. Wi-Fi setup information
4. Choose who is being monitored and name the room
5. Alert preferences
6. Notification preferences
7. Motion test
8. Create account with caregiver name, email, required phone number, password, and password confirmation
9. Setup complete

## Device ID Persistence

During onboarding, Bluetooth discovery provides the monitor identifier. The current beta monitor resolves to:

```text
bathroom-monitor-001
```

`DeviceIdentityStore` defines the persistence boundary. `UserDefaultsDeviceIdentityStore` stores the normalized device ID so it does not change every launch. A Keychain-backed implementation can replace it later when production authentication is added.

## Supabase Setup

The app reads `motion_events` today and will also read `devices` when that table exists. It uses the saved monitor device ID to filter motion rows:

```text
motion_events.device_id = bathroom-monitor-001
```

To connect a local build:

1. Copy `Configuration/Supabase.example.plist` to `Configuration/Supabase.plist`.
2. Set `SUPABASE_URL`.
3. Set `SUPABASE_ANON_KEY`.
4. Set `ELEPH_DEVICE_ID` if your monitor ID differs from `bathroom-monitor-001`.

`Configuration/Supabase.plist` is ignored by git. Use only a public anon key in the app. Never ship a service-role key.

The app uses `AppServiceContainer.liveOrMock()`: if Supabase configuration is present, it creates `SupabaseAppRepository`; otherwise it uses `MockAppRepository`.

The Supabase schema needs select access for the iOS app. Apply `../supabase/schema.sql` so `motion_events` and optional `devices` read policies are present.

## Future Integrations

The frontend is prepared for production services through protocols:

- `BluetoothProvisioningService`: replace `MockBluetoothProvisioningService` with Core Bluetooth setup.
- `WiFiProvisioningService`: send Wi-Fi credentials to the monitor after Bluetooth connection.
- `AuthenticationService`: connect Sign in with Apple, Google, or email auth.
- `DeviceRepository`: currently reads Supabase `devices` when available and falls back to local device identity.
- `MotionEventRepository`: currently reads Supabase `motion_events` where `motion_events.device_id` matches the saved monitor ID.
- `AlertRepository`: later persist alert preferences and read alert history.

Supabase code belongs in repository implementations, not directly inside SwiftUI views.

## Development

Open `ios/Package.swift` in Xcode or validate from the command line:

```bash
cd ios
swift build
```

The Swift package intentionally has no third-party UI framework dependency.
