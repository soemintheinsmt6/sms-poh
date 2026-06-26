import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/socket_config.dart';
import '../models/sms_request.dart';
import '../models/socket_status.dart';

/// Data layer for the realtime SMS feed.
///
/// Speaks the Pusher protocol (Laravel Reverb) directly over a raw WebSocket so
/// it can target the self-hosted `/app/{appKey}` endpoint. Wraps everything so
/// the rest of the app only ever sees [SocketStatus] and [SmsRequest].
///
/// Flow: connect → receive `pusher:connection_established` → subscribe to the
/// channel → receive broadcast events whose `data` is `{phone_number, otp}`.
/// Mirrors the proven setup in the fight_zone project, including auto-reconnect
/// with exponential backoff. Every frame is logged under the `SocketService`
/// name (visible in `flutter run` / IDE logcat) so the feed can be debugged.
class SocketService {
  SocketService(this._config);

  final SocketConfig _config;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _intentionallyClosed = false;
  String? _socketId;

  static const int _maxReconnectDelay = 30;

  final StreamController<SocketStatus> _statusController =
      StreamController<SocketStatus>.broadcast();
  final StreamController<SmsRequest> _requestController =
      StreamController<SmsRequest>.broadcast();

  /// Live connection status.
  Stream<SocketStatus> get statusStream => _statusController.stream;

  /// SMS-send requests as they arrive on the configured channel.
  Stream<SmsRequest> get requestStream => _requestController.stream;

  SocketStatus _status = SocketStatus.disconnected;
  SocketStatus get status => _status;

  void _log(String message) => developer.log(message, name: 'SocketService');

  void _setStatus(SocketStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  /// Opens the connection. No-op if already connected/connecting.
  Future<void> connect() async {
    if (_status == SocketStatus.connecting ||
        _status == SocketStatus.connected) {
      return;
    }
    _intentionallyClosed = false;
    _reconnectTimer?.cancel();
    _setStatus(SocketStatus.connecting);

    try {
      _log('Connecting to ${_config.url}');
      final channel = WebSocketChannel.connect(Uri.parse(_config.url));
      _channel = channel;
      await channel.ready;
      _reconnectAttempts = 0;

      _subscription = channel.stream.listen(
        _onData,
        onError: (Object error) {
          _log('Error: $error');
          _handleDisconnect();
        },
        onDone: () {
          _log('Connection closed (code ${channel.closeCode})');
          _handleDisconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      _log('Connect failed: $e');
      _handleDisconnect();
    }
  }

  /// Closes the connection on purpose and stops auto-reconnect.
  Future<void> disconnect() async {
    _intentionallyClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _socketId = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
    _setStatus(SocketStatus.disconnected);
  }

  void _onData(dynamic raw) {
    _log('Received: $raw');
    final map = _decode(raw);
    if (map == null) return;

    final event = map['event'] as String?;
    switch (event) {
      case 'pusher:connection_established':
        _socketId = _decode(map['data'])?['socket_id']?.toString();
        _log('Connection established (socket_id=$_socketId)');
        _setStatus(SocketStatus.connected);
        _subscribe();
      case 'pusher_internal:subscription_succeeded':
        _log('Subscribed to ${map['channel']}');
      case 'pusher:ping':
        _channel?.sink.add(jsonEncode({'event': 'pusher:pong'}));
      case 'pusher:error':
        _log('Pusher error: ${map['data']}');
        _setStatus(SocketStatus.error);
      default:
        // Any non-Pusher event on our channel is a broadcast payload.
        if (event != null &&
            !event.startsWith('pusher') &&
            map['channel'] == _config.channel) {
          final request = _parsePayload(map['data']);
          if (request != null &&
              request.isValid &&
              !_requestController.isClosed) {
            _log('Request received for ${request.phoneNumber}');
            _requestController.add(request);
          }
        }
    }
  }

  void _subscribe() {
    _log('Subscribing to ${_config.channel}');
    _channel?.sink.add(
      jsonEncode({
        'event': 'pusher:subscribe',
        'data': {'channel': _config.channel},
      }),
    );
  }

  void _handleDisconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _socketId = null;
    if (_intentionallyClosed) {
      _setStatus(SocketStatus.disconnected);
      return;
    }
    _setStatus(SocketStatus.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = _reconnectDelay();
    _log('Reconnecting in ${delay}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _reconnectAttempts++;
      connect();
    });
  }

  int _reconnectDelay() {
    // Exponential 1,2,4,8,16,32 capped at 30 (exponent capped to avoid overflow).
    final exponent = _reconnectAttempts > 5 ? 5 : _reconnectAttempts;
    final delay = 1 << exponent;
    return delay > _maxReconnectDelay ? _maxReconnectDelay : delay;
  }

  /// Decodes a JSON frame or an already-decoded map into a `Map`.
  Map<String, dynamic>? _decode(dynamic raw) {
    try {
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } else if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (_) {
      // Ignore non-JSON frames.
    }
    return null;
  }

  /// Decodes an event's `data` (Pusher double-encodes it as a JSON string).
  SmsRequest? _parsePayload(dynamic data) {
    final map = _decode(data);
    return map == null ? null : SmsRequest.fromJson(map);
  }

  /// Releases the connection and the stream controllers. Call once, on teardown.
  void dispose() {
    _intentionallyClosed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
    _statusController.close();
    _requestController.close();
  }
}
