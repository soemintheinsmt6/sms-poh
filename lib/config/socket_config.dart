import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Connection settings for the Pusher-protocol (Reverb) socket.
///
/// Built from the `.env` values `WEBSOCKET_URL`, `KEY`, `CHANNEL_NAME`. The
/// URL already includes the Reverb `/app/{appKey}` path, so it is used as-is —
/// only the Pusher protocol query params are appended.
class SocketConfig {
  const SocketConfig({
    required this.url,
    required this.channel,
    required this.authKey,
  });

  /// Full websocket URL, e.g. `wss://host/app/{appKey}`.
  final String url;

  /// Channel to subscribe to (e.g. `otp-sms-requests`).
  final String channel;

  /// The `KEY` env value. Not needed for a public channel; kept for
  /// private/presence channel authorization if the backend later requires it.
  final String authKey;

  factory SocketConfig.fromEnv() => SocketConfig(
    url: dotenv.env['WEBSOCKET_URL'] ?? '',
    channel: dotenv.env['CHANNEL_NAME'] ?? '',
    authKey: dotenv.env['KEY'] ?? '',
  );
}
