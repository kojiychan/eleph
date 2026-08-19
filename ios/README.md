# Eleph iOS

SwiftUI iOS 17+ companion app for the Eleph bathroom monitor. This frontend helps a caregiver quickly answer: "Do I need to check on my loved one?"

## Current Status

The app can read real Supabase motion data, create Supabase Auth accounts, and save beta user/device settings when configured. Debug builds fall back to realistic mock data when no local Supabase configuration exists. TestFlight and release builds require Supabase configuration.

- No production Bluetooth or Wi-Fi provisioning is implemented.
- Notification delivery is not implemented.
- No Supabase credentials are hardcoded or required.

## Architecture

The app uses SwiftUI with MVVM-style view models and async/await-ready service protocols.

- `Models/`: `MonitorDevice`, `MotionEvent`, `AlertEvent`, `AlertPreferences`, `NighttimeSchedule`, `UserProfile`, `CaregiverContact`, and `DailyActivitySummary`.
- `Views/`: onboarding, Home, Activity, Settings, and tab navigation.
- `ViewModels/`: screen state and user actions.
- `Services/`: repository and integration protocols plus Supabase and mock implementations.
- `Components/`: reusable cards, banners, timeline, metric cards, threshold picker, empty/loading/error states, and onboarding progress.
- `Utilities/`: configuration, formatting helpers, colors, loadable state, and preview scenarios.
- `Legal/`: bundled Privacy Policy and Terms and Conditions text displayed from Settings.

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

For the first TestFlight beta, new-user setup is intentionally tied to the existing monitor (`bathroom-monitor-001`) and includes:

1. Choose who is being monitored and name the room
2. Alert preferences
3. Notification preferences
4. Create account with first name, last name, email, required phone number, password, and password confirmation
5. Setup complete

## Device ID Persistence

During beta onboarding, the app assigns the existing monitor identifier automatically:

```text
bathroom-monitor-001
```

`DeviceIdentityStore` defines the persistence boundary. `UserDefaultsDeviceIdentityStore` stores the normalized device ID so it does not change every launch. Phase 2 can replace the beta assignment with Bluetooth discovery and Wi-Fi provisioning.

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
5. Optionally set legal/support URLs:
   - `ELEPH_PRIVACY_POLICY_URL`
   - `ELEPH_TERMS_URL`
   - `ELEPH_SUPPORT_URL`
   - `ELEPH_DATA_DELETION_URL`

`Configuration/Supabase.plist` is ignored by git. Use only a public anon key in the app. Never ship a service-role key.

The app uses `AppServiceContainer.liveOrMock()`: if Supabase configuration is present, it creates `SupabaseAppRepository`; otherwise debug builds use `MockAppRepository`. Release/TestFlight builds fail fast if configuration is missing.

The Supabase schema needs Auth, profile, device link, device settings, device, and motion event policies for the iOS app. Apply `../supabase/schema.sql`.

## Future Integrations

The frontend is prepared for production services through protocols:

- `BluetoothProvisioningService`: replace `MockBluetoothProvisioningService` with Core Bluetooth setup.
- `WiFiProvisioningService`: send Wi-Fi credentials to the monitor after Bluetooth connection.
- `AuthenticationService`: Supabase email/password auth is implemented. Sign in with Apple and Google are intentionally disabled for this beta.
- `DeviceRepository`: currently reads Supabase `devices` when available and falls back to local device identity.
- `MotionEventRepository`: currently reads Supabase `motion_events` where `motion_events.device_id` matches the saved monitor ID.
- `AlertRepository`: later persist alert preferences and read alert history.

Supabase code belongs in repository implementations, not directly inside SwiftUI views.

## Legal and Support

Settings includes in-app Privacy Policy and Terms and Conditions screens using the bundled markdown documents. Settings also includes links for support and account/data deletion requests. Until public web pages are available, the beta defaults route support and deletion requests to `kojiychan@gmail.com`.

## Development

Open `ios/Package.swift` in Xcode or validate from the command line:

```bash
cd ios
swift build
```

The Swift package intentionally has no third-party UI framework dependency.
