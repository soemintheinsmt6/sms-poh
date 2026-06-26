// Smoke test for the start screen.
//
// Uses a fake RelayServiceController so the test never touches the platform-only
// flutter_background_service. Verifies the initial UI renders.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sms_poh/models/sms_request.dart';
import 'package:sms_poh/models/socket_status.dart';
import 'package:sms_poh/services/relay_service_controller.dart';
import 'package:sms_poh/services/sms_service.dart';
import 'package:sms_poh/views/start_view.dart';

class _FakeRelayService implements RelayServiceController {
  final _status = StreamController<SocketStatus>.broadcast();
  final _request = StreamController<SmsRequest>.broadcast();
  final _sms = StreamController<String>.broadcast();

  @override
  Stream<SocketStatus> get statusStream => _status.stream;
  @override
  Stream<SmsRequest> get requestStream => _request.stream;
  @override
  Stream<String> get smsResultStream => _sms.stream;

  @override
  Future<bool> isRunning() async => false;
  @override
  Future<void> start() async {}
  @override
  void stop() {}
  @override
  Future<void> ensurePermissions() async {}

  void dispose() {
    _status.close();
    _request.close();
    _sms.close();
  }
}

void main() {
  testWidgets('start screen shows disconnected status and waiting state', (
    WidgetTester tester,
  ) async {
    final fake = _FakeRelayService();
    addTearDown(fake.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: StartView(
          service: fake,
          smsService: SmsService(),
          autoStart: false,
        ),
      ),
    );

    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('No codes yet'), findsOneWidget);
    expect(find.text('Start listening'), findsOneWidget);
    expect(find.text('Open SMS sender'), findsOneWidget);
  });
}
