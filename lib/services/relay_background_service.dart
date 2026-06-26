import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/socket_config.dart';
import '../models/sms_request.dart';
import '../models/socket_status.dart';
import '../models/sms_send_result.dart';
import 'relay_service_controller.dart';
import 'sms_service.dart';
import 'socket_service.dart';

/// Notification channel that backs the persistent foreground-service notification.
const String kRelayServiceChannelId = 'otp_listener';

/// Notification channel for one-off "SMS sent" alerts.
const String kRelayEventsChannelId = 'otp_events';

const int _serviceNotificationId = 888;

/// UI-facing controller for the background relay service.
///
/// The WebSocket and the SMS auto-send run in a **separate background isolate**
/// ([relayServiceOnStart]) so they survive the app being minimized/closed. This
/// class is how the UI starts/stops that isolate and observes its status + send
/// events over `flutter_background_service`'s IPC channel.
class RelayBackgroundService implements RelayServiceController {
  final FlutterBackgroundService _service = FlutterBackgroundService();

  @override
  Stream<SocketStatus> get statusStream =>
      _service.on('status').map((event) => _statusFrom(event?['status']));

  @override
  Stream<SmsRequest> get requestStream => _service.on('request').map(
    (event) => SmsRequest(
      phoneNumber: event?['phone_number']?.toString() ?? '',
      code: event?['code']?.toString() ?? '',
    ),
  );

  @override
  Stream<String> get smsResultStream =>
      _service.on('sms').map((event) => event?['message']?.toString() ?? '');

  @override
  Future<bool> isRunning() => _service.isRunning();

  @override
  Future<void> start() async {
    if (!await _service.isRunning()) {
      await _service.startService();
    }
    _service.invoke('sync');
  }

  @override
  void stop() => _service.invoke('stop');

  @override
  Future<void> ensurePermissions() async {
    await Permission.sms.request();
    await Permission.notification.request();
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  static SocketStatus _statusFrom(dynamic name) =>
      SocketStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => SocketStatus.disconnected,
      );
}

/// Creates the notification channels and configures the background service.
/// Call once from `main()` before `runApp`.
Future<void> configureRelayBackgroundService() async {
  final notifications = FlutterLocalNotificationsPlugin();
  final android = notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      kRelayServiceChannelId,
      'Verification Listener',
      description: 'Keeps the verification socket connected in the background',
      importance: Importance.low,
    ),
  );
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      kRelayEventsChannelId,
      'Verification Events',
      description: 'Alerts when a verification SMS is sent',
      importance: Importance.high,
    ),
  );

  await FlutterBackgroundService().configure(
    androidConfiguration: AndroidConfiguration(
      onStart: relayServiceOnStart,
      isForegroundMode: true,
      autoStart: true,
      autoStartOnBoot: true,
      notificationChannelId: kRelayServiceChannelId,
      initialNotificationTitle: 'Verification Listener',
      initialNotificationContent: 'Starting…',
      foregroundServiceNotificationId: _serviceNotificationId,
      foregroundServiceTypes: const [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

/// Background isolate entry point: runs the socket and auto-sends SMS.
@pragma('vm:entry-point')
void relayServiceOnStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final socket = SocketService(SocketConfig.fromEnv());
  final sms = SmsService();
  final notifications = FlutterLocalNotificationsPlugin();

  var lastStatus = SocketStatus.disconnected;
  SmsRequest? lastRequest;

  void updateNotification(String content) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Verification Listener',
        content: content,
      );
    }
  }

  socket.statusStream.listen((status) {
    lastStatus = status;
    service.invoke('status', {'status': status.name});
    updateNotification('WebSocket: ${status.name}');
  });

  socket.requestStream.listen((request) async {
    lastRequest = request;
    service.invoke('request', {
      'phone_number': request.phoneNumber,
      'code': request.code,
    });

    final smsBody = 'Your verification code is ${request.code}';
    final result = await sms.sendSms(to: request.phoneNumber, message: smsBody);
    final ok = result == SmsSendResult.sent;
    final summary = ok
        ? 'Sent verification to ${request.phoneNumber}'
        : 'Send failed for ${request.phoneNumber} (${result.name})';
    service.invoke('sms', {'message': summary});
    updateNotification(summary);

    await notifications.show(
      request.phoneNumber.hashCode & 0x7fffffff,
      ok ? 'Verification sent' : 'Verification failed',
      summary,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          kRelayEventsChannelId,
          'Verification Events',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  });

  // The UI calls this on open to fetch the current state (late subscribers
  // would otherwise miss the status emitted before they attached).
  service.on('sync').listen((event) {
    service.invoke('status', {'status': lastStatus.name});
    final request = lastRequest;
    if (request != null) {
      service.invoke('request', {
        'phone_number': request.phoneNumber,
        'code': request.code,
      });
    }
  });

  service.on('stop').listen((event) async {
    await socket.disconnect();
    await service.stopSelf();
  });

  socket.connect();
}
