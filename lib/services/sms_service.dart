import 'dart:developer' as developer;

import 'package:another_telephony/telephony.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:permission_handler/permission_handler.dart';

import '../models/sms_send_result.dart';

/// Data layer for sending SMS.
///
/// Wraps the platform SMS + permission plugins so the rest of the app never
/// imports `another_telephony` or `permission_handler` directly. Swap or fake
/// this class to test the view-model without touching the platform.
class SmsService {
  SmsService({Telephony? telephony})
    : _telephony = telephony ?? Telephony.instance;

  final Telephony _telephony;

  void _log(String message) => developer.log(message, name: 'SmsService');

  /// Ensures the SEND_SMS permission and, if granted, sends [message] to [to]
  /// silently through the device's default SMS SIM (no compose screen).
  ///
  /// Checks the current status first and only calls `request()` when needed, so
  /// it is safe to call from a background isolate (which can't show a dialog) as
  /// long as the permission was already granted while in the foreground.
  Future<SmsSendResult> sendSms({
    required String to,
    required String message,
  }) async {
    var status = await Permission.sms.status;
    if (!status.isGranted) {
      status = await Permission.sms.request();
    }
    if (!status.isGranted) {
      return status.isPermanentlyDenied
          ? SmsSendResult.permissionPermanentlyDenied
          : SmsSendResult.permissionDenied;
    }

    try {
      await _telephony.sendSms(
        to: to,
        message: message,
        // Observability only. `another_telephony` forwards Android's sent/
        // delivered broadcasts here, but it does NOT inspect their result code
        // (see SmsMethodCallHandler.onReceive), so SENT means "the attempt
        // finished", not "the carrier accepted it". We log it to diagnose the
        // silent drops that burst-throttling causes; we must not treat the
        // absence of a status as a failure, or a retry would duplicate the SMS.
        statusListener: (status) => _log('Send status for $to: ${status.name}'),
      );
      return SmsSendResult.sent;
    } on PlatformException catch (e) {
      // The native call rejected the message before dispatching it. Nothing
      // left the device, so this outcome is safe to retry.
      _log('sendSms platform error for $to: ${e.code} ${e.message}');
      return SmsSendResult.failed;
    }
  }
}
