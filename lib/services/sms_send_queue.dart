import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import '../models/sms_send_result.dart';
import 'sms_service.dart';

/// Serializes outgoing SMS so only one is dispatched at a time, spaced apart,
/// with bounded retries for pre-dispatch failures.
///
/// ## Why this exists
///
/// Android and mobile carriers silently rate-limit *bursts* of SMS. When
/// several socket requests arrive at once and the app fires `sendTextMessage`
/// back-to-back, the carrier drops some messages over the air while the device
/// still records them locally as "sent" — the exact "shows as sent, never
/// received" symptom, and only under simultaneous sends. Draining the queue one
/// message at a time, each [_gap] apart, keeps the app under that burst limit.
///
/// ## Why retries are narrow
///
/// The underlying plugin cannot distinguish a delivered SMS from a throttled
/// one (it discards Android's send result code), so a message that may already
/// have left the device is **never** retried — that would duplicate the OTP.
/// Only [SmsSendResult.failed] (a failure *before* dispatch) is retried, with
/// exponential backoff; permission outcomes are returned untouched.
class SmsSendQueue {
  SmsSendQueue(
    this._sms, {
    Duration gap = const Duration(seconds: 3),
    int maxAttempts = 3,
    Duration initialBackoff = const Duration(seconds: 2),
  })  : _gap = gap,
        _maxAttempts = maxAttempts,
        _initialBackoff = initialBackoff;

  final SmsService _sms;

  /// Minimum spacing between two consecutive sends.
  final Duration _gap;

  /// Total dispatch attempts per message, including the first.
  final int _maxAttempts;

  /// Delay before the first retry; doubled on each subsequent retry.
  final Duration _initialBackoff;

  final Queue<_PendingSend> _pending = Queue<_PendingSend>();
  bool _draining = false;

  void _log(String message) => developer.log(message, name: 'SmsSendQueue');

  /// Queues [message] to [to] and returns the final outcome after any retries.
  ///
  /// Messages are sent strictly in enqueue order and never overlap, so callers
  /// can enqueue freely from a burst of events without racing the SIM.
  Future<SmsSendResult> enqueue({
    required String to,
    required String message,
  }) {
    final item = _PendingSend(to, message);
    _pending.add(item);
    _log('Queued send to $to (${_pending.length} pending)');
    unawaited(_drain());
    return item.completer.future;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        final item = _pending.removeFirst();
        final result = await _sendWithRetry(item.to, item.message);
        item.completer.complete(result);
        // Space the *next* send apart; no need to wait after the last one.
        if (_pending.isNotEmpty) {
          await Future<void>.delayed(_gap);
        }
      }
    } finally {
      _draining = false;
    }
  }

  Future<SmsSendResult> _sendWithRetry(String to, String message) async {
    var backoff = _initialBackoff;
    for (var attempt = 1;; attempt++) {
      final result = await _sms.sendSms(to: to, message: message);
      // Retry only a definitive pre-dispatch failure; sent/permission outcomes
      // are final. Retrying anything else risks a duplicate SMS.
      if (result != SmsSendResult.failed || attempt >= _maxAttempts) {
        if (result == SmsSendResult.failed) {
          _log('Giving up on $to after $attempt attempt(s)');
        }
        return result;
      }
      _log('Send to $to failed (attempt $attempt); retrying in '
          '${backoff.inSeconds}s');
      await Future<void>.delayed(backoff);
      backoff *= 2;
    }
  }
}

class _PendingSend {
  _PendingSend(this.to, this.message);

  final String to;
  final String message;
  final Completer<SmsSendResult> completer = Completer<SmsSendResult>();
}
