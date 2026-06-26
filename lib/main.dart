import 'package:flutter/material.dart';

import 'services/relay_background_service.dart';
import 'services/sms_service.dart';
import 'views/start_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sets up the notification channels and the foreground service. The service's
  // background isolate loads its own `.env` (see relayServiceOnStart).
  await configureRelayBackgroundService();
  runApp(MyApp(service: RelayBackgroundService(), smsService: SmsService()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.service, required this.smsService});

  final RelayBackgroundService service;
  final SmsService smsService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMSPoh',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: StartView(service: service, smsService: smsService),
    );
  }
}
