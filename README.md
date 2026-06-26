# sms_poh

An **Android-only** SMS-relay app. It listens to a realtime WebSocket feed and
sends an SMS **directly through the SIM** — no system compose screen, no second
confirmation tap. This silent send is the entire point of the project.

The socket runs inside a **foreground service** in a background isolate, so the
app stays connected and auto-sends an SMS for each incoming message even while it
is minimized, closed, or after a reboot. A persistent notification is always
shown while the service runs (mandatory on Android).

> **Android only.** iOS cannot send SMS without a user-driven compose screen, so
> the app is not expected to function on iOS even though the Flutter project
> nominally supports it.

## How it works

- **Transport.** The WebSocket backend is **Laravel Reverb** (Pusher protocol).
  The app does *not* use a Pusher SDK — `pusher_channels_flutter` only targets
  Pusher's hosted cloud and cannot reach a self-hosted `/app/{appKey}` endpoint —
  so the Pusher protocol is spoken directly over a raw `web_socket_channel`.
- **Flow.** connect → on `pusher:connection_established`, subscribe to the
  channel → each non-`pusher:*` event carries the double-encoded message payload
  (a phone number and the SMS body) → the SMS is auto-sent through the system
  default SIM. The socket replies `pong` to `pusher:ping` and auto-reconnects
  with exponential backoff (capped at 30s).
- **Isolates.** The socket + SMS-send logic live in the background-service
  isolate; the UI observes state over IPC. The `.env` is loaded inside the
  background isolate (where the socket actually runs).

## Getting started

1. **Install dependencies**

   ```bash
   flutter pub get
   ```

2. **Configure `.env`** — copy the committed template and fill in your values.
   The `.env` is git-ignored and declared as an asset in `pubspec.yaml`.

   ```bash
   cp .env.example .env
   ```

   | Key             | Description                                                              |
   | --------------- | ------------------------------------------------------------------------ |
   | `WEBSOCKET_URL` | Full Reverb URL including the `/app/{appKey}` path (e.g. `wss://host/app/key`). |
   | `KEY`           | Kept for private-channel auth; not needed for the current public channel. |
   | `CHANNEL_NAME`  | The channel to subscribe to (e.g. `otp-sms-requests`).                    |

3. **Run on a real device**

   ```bash
   flutter run
   ```

   On launch the start screen requests the `SEND_SMS`, `POST_NOTIFICATIONS`, and
   battery-optimization-exemption permissions, then starts the foreground service.

## Commands

```bash
flutter pub get          # install dependencies (after editing pubspec.yaml)
flutter run              # run on a connected device
flutter analyze          # static analysis / lint
flutter test             # run all tests
flutter test test/widget_test.dart --plain-name "name"   # run a single test by name
```

## Runtime requirements

- **Real device only.** An emulator has no SIM, so a real send will not go
  through; the emulator only exercises the UI and the permission flow.
- **Default SIM.** The app sends through the system default SMS SIM. On a
  dual-SIM phone, set the default in Android (SIM manager → Messages). The code
  does not pick a SIM — `another_telephony` has no per-SIM selection. Forcing a
  specific SIM would require a platform channel calling
  `SmsManager.createForSubscriptionId(subId)` in `MainActivity.kt` (not
  implemented).
- **Permissions must be granted in the foreground first.** A background isolate
  cannot show permission dialogs, so `SEND_SMS` (plus `POST_NOTIFICATIONS` and
  the battery-optimization exemption) must be granted while the app is in the
  foreground; the service then works in the background.
- **`SEND_SMS` is Play-Store-restricted.** This app targets personal/sideload
  use. Publishing to Play would require it to be the default SMS handler or a
  permissions declaration.
- **`targetSdk` is pinned at 34** in `build.gradle.kts`. Android 15 (target 35+)
  caps a `dataSync` foreground service to ~6h/day, which would kill the always-on
  listener. If you bump `targetSdk`, switch the service type to `specialUse` (or
  accept the time limit).
- **Core-library desugaring is required** by `flutter_local_notifications`
  (enabled in `build.gradle.kts`). Removing it breaks the Android build.

## Architecture

MVVM, one layer per directory under `lib/`, with a strict dependency direction:
**view → view-model → service → model** (never reach backwards).

- **Services own all platform/plugin imports** so upper layers see only domain
  types (`SmsSendResult`, `SocketStatus`, `OtpMessage`).
- **View-models import only `flutter/widgets`** (no `material`, no `BuildContext`,
  no plugins) and are unit-testable in isolation.
- There is no DI framework; `main.dart` constructs the services and injects them
  down through constructors.

The app has two independent vertical slices:

### Message listener (home route)

| File                                      | Responsibility                                                                 |
| ----------------------------------------- | ----------------------------------------------------------------------------- |
| `models/socket_status.dart`               | `SocketStatus` enum.                                                           |
| `models/otp_message.dart`                 | The incoming message value object (`fromJson`, `isValid`).                     |
| `config/socket_config.dart`              | `SocketConfig.fromEnv()` reads `url`, `channel`, `authKey`.                    |
| `services/socket_service.dart`            | Speaks the Pusher protocol by hand over `web_socket_channel`; runs in the background isolate. |
| `services/otp_service_controller.dart`    | Abstract interface the UI/view-model depend on (keeps them testable).          |
| `services/otp_background_service.dart`    | Real implementation: UI-side bridge, `configureOtpBackgroundService()`, and the `otpServiceOnStart` background isolate that loads `.env`, runs the socket, and auto-sends an SMS for each incoming message. |
| `viewmodels/start_viewmodel.dart`         | Bridges controller streams into getters; `dispose()` does **not** stop the service (it must outlive the screen). |
| `views/start_view.dart`                   | Live status, start/stop controls, the latest message, SMS-result snackbars; requests permissions and starts the service on mount. |

### SMS sender (pushed from the start screen)

| File                                  | Responsibility                                                                  |
| ------------------------------------- | ------------------------------------------------------------------------------ |
| `models/sms_send_result.dart`         | `SmsSendResult` enum (the send outcome).                                        |
| `services/sms_service.dart`           | Only file importing `another_telephony` and `permission_handler`; `sendSms()` requests `SEND_SMS`, sends through the default SIM, returns an `SmsSendResult`. |
| `viewmodels/send_sms_viewmodel.dart`  | Owns the `TextEditingController`s, the `sending` flag, and `feedback`; validates input. |
| `views/send_sms_view.dart`            | Pure UI; rebuilds via `ListenableBuilder`, shows `feedback` as a snackbar.      |

### Native wiring (must stay in sync)

- `android/app/src/main/AndroidManifest.xml` — declares `SEND_SMS`, `INTERNET`,
  the foreground-service permissions, and merges
  `android:foregroundServiceType="dataSync"` into the `flutter_background_service`
  service entry.
- `android/app/build.gradle.kts` — pins `targetSdk = 34` and enables core-library
  desugaring.
- `pubspec.yaml` — pins `another_telephony`, `permission_handler`,
  `web_socket_channel`, `flutter_dotenv`, `flutter_background_service`,
  `flutter_local_notifications`; lists `.env` under `flutter: assets`.
- `android/app/src/main/kotlin/com/deliver/sms_poh/MainActivity.kt` — the default
  Flutter activity; the place to add a method channel if explicit SIM selection
  is ever needed.
