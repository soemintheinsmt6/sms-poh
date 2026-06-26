import 'package:another_telephony/telephony.dart';
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

    await _telephony.sendSms(to: to, message: message);
    return SmsSendResult.sent;
  }
}
