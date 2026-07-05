import 'package:flutter_test/flutter_test.dart';
import 'package:sms_poh/models/sms_send_result.dart';
import 'package:sms_poh/services/sms_send_queue.dart';
import 'package:sms_poh/services/sms_service.dart';

/// Records every send, enforces that no two sends overlap, and returns a
/// scripted result per phone number.
class _FakeSmsService extends SmsService {
  _FakeSmsService(this._script);

  /// phone number -> list of results to return, one per attempt.
  final Map<String, List<SmsSendResult>> _script;

  final List<String> sendOrder = <String>[];
  int _inFlight = 0;
  int maxConcurrent = 0;

  @override
  Future<SmsSendResult> sendSms({
    required String to,
    required String message,
  }) async {
    _inFlight++;
    maxConcurrent = maxConcurrent > _inFlight ? maxConcurrent : _inFlight;
    sendOrder.add(to);
    // Yield so any (incorrectly) concurrent send would overlap here.
    await Future<void>.delayed(Duration.zero);
    _inFlight--;
    final results = _script[to]!;
    return results.length == 1 ? results.first : results.removeAt(0);
  }
}

void main() {
  // SmsService's constructor reaches Telephony.instance, which sets a method
  // call handler — that needs a binary messenger from the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Zero gap/backoff keeps the tests fast; timing is orthogonal to the logic.
  SmsSendQueue queueFor(_FakeSmsService fake) => SmsSendQueue(
    fake,
    gap: Duration.zero,
    initialBackoff: Duration.zero,
    maxAttempts: 3,
  );

  test('sends one at a time, never overlapping', () async {
    final fake = _FakeSmsService({
      '111': [SmsSendResult.sent],
      '222': [SmsSendResult.sent],
      '333': [SmsSendResult.sent],
    });
    final queue = queueFor(fake);

    // Enqueue a burst without awaiting — mimics simultaneous socket requests.
    final futures = [
      queue.enqueue(to: '111', message: 'a'),
      queue.enqueue(to: '222', message: 'b'),
      queue.enqueue(to: '333', message: 'c'),
    ];
    final results = await Future.wait(futures);

    expect(results, everyElement(SmsSendResult.sent));
    expect(fake.maxConcurrent, 1, reason: 'sends must be serialized');
    expect(fake.sendOrder, ['111', '222', '333'], reason: 'FIFO order');
  });

  test('retries a pre-dispatch failure, then succeeds', () async {
    final fake = _FakeSmsService({
      '111': [SmsSendResult.failed, SmsSendResult.sent],
    });
    final queue = queueFor(fake);

    final result = await queue.enqueue(to: '111', message: 'a');

    expect(result, SmsSendResult.sent);
    expect(fake.sendOrder, ['111', '111'], reason: 'one retry');
  });

  test('gives up after maxAttempts on persistent failure', () async {
    final fake = _FakeSmsService({
      '111': [
        SmsSendResult.failed,
        SmsSendResult.failed,
        SmsSendResult.failed,
        SmsSendResult.sent, // should never be reached
      ],
    });
    final queue = queueFor(fake);

    final result = await queue.enqueue(to: '111', message: 'a');

    expect(result, SmsSendResult.failed);
    expect(fake.sendOrder.length, 3, reason: 'capped at maxAttempts');
  });

  test('never retries a permission outcome (no duplicate risk)', () async {
    final fake = _FakeSmsService({
      '111': [SmsSendResult.permissionDenied, SmsSendResult.sent],
    });
    final queue = queueFor(fake);

    final result = await queue.enqueue(to: '111', message: 'a');

    expect(result, SmsSendResult.permissionDenied);
    expect(fake.sendOrder, ['111'], reason: 'permission failures are final');
  });
}
