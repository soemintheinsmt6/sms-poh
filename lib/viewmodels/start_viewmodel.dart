import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/sms_request.dart';
import '../models/socket_status.dart';
import '../services/relay_service_controller.dart';

/// View-model for the start screen.
///
/// Reflects the state of the background verification service
/// ([RelayServiceController]) and forwards start/stop actions. Holds no
/// `BuildContext` and imports no platform plugins.
///
/// Note: [dispose] does **not** stop the service — the whole point is that it
/// keeps running after the screen (and app) goes away.
class StartViewModel extends ChangeNotifier {
  StartViewModel(this._service) {
    _statusSub = _service.statusStream.listen((status) {
      _status = status;
      notifyListeners();
    });
    _requestSub = _service.requestStream.listen((message) {
      _lastMessage = message;
      _lastReceivedAt = DateTime.now();
      // Clear the previous send result so the chip shows "Sending…" until this
      // code's own result arrives.
      _lastSmsResult = null;
      _lastResultAt = null;
      notifyListeners();
    });
    _smsSub = _service.smsResultStream.listen((result) {
      _lastSmsResult = result;
      _lastResultAt = DateTime.now();
      notifyListeners();
    });
  }

  final RelayServiceController _service;

  late final StreamSubscription<SocketStatus> _statusSub;
  late final StreamSubscription<SmsRequest> _requestSub;
  late final StreamSubscription<String> _smsSub;

  SocketStatus _status = SocketStatus.disconnected;
  SocketStatus get status => _status;

  SmsRequest? _lastMessage;
  SmsRequest? get lastMessage => _lastMessage;

  DateTime? _lastReceivedAt;
  DateTime? get lastReceivedAt => _lastReceivedAt;

  String? _lastSmsResult;
  String? get lastSmsResult => _lastSmsResult;

  DateTime? _lastResultAt;
  DateTime? get lastResultAt => _lastResultAt;

  /// null = no send yet, true = last send succeeded, false = it failed.
  bool? get lastSendOk => _lastSmsResult?.toLowerCase().startsWith('sent');

  Future<void> ensurePermissions() => _service.ensurePermissions();

  Future<void> start() => _service.start();

  void stop() => _service.stop();

  @override
  void dispose() {
    _statusSub.cancel();
    _requestSub.cancel();
    _smsSub.cancel();
    super.dispose();
  }
}
