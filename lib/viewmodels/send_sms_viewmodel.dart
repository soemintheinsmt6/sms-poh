import 'package:flutter/widgets.dart';

import '../models/sms_send_result.dart';
import '../services/sms_service.dart';

/// View-model for the send-SMS screen.
///
/// Owns the form state and the send logic, and exposes them as plain
/// getters. Holds no `BuildContext` and imports no `material`/platform code,
/// so it can be unit-tested with a faked [SmsService].
class SendSmsViewModel extends ChangeNotifier {
  SendSmsViewModel(this._smsService);

  final SmsService _smsService;

  final TextEditingController numberController = TextEditingController();
  final TextEditingController messageController = TextEditingController();

  bool _sending = false;
  bool get sending => _sending;

  /// Last user-facing message (validation error or send result). The view
  /// reads this after [sendSms] completes to show a snackbar.
  String? _feedback;
  String? get feedback => _feedback;

  /// Validates the form and sends the SMS through the [SmsService].
  Future<void> sendSms() async {
    final number = numberController.text.trim();
    final message = messageController.text.trim();

    if (number.isEmpty || message.isEmpty) {
      _feedback = 'Enter both a number and a message.';
      notifyListeners();
      return;
    }

    _sending = true;
    _feedback = null;
    notifyListeners();

    try {
      final result = await _smsService.sendSms(to: number, message: message);
      _feedback = switch (result) {
        SmsSendResult.sent => 'SMS sent to $number on the default SIM.',
        SmsSendResult.permissionDenied => 'SMS permission is required to send.',
        SmsSendResult.permissionPermanentlyDenied =>
          'SMS permission denied. Enable it in Settings.',
      };
    } catch (e) {
      _feedback = 'Failed to send: $e';
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    numberController.dispose();
    messageController.dispose();
    super.dispose();
  }
}
