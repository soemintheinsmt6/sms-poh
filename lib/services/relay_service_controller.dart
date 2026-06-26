import '../models/sms_request.dart';
import '../models/socket_status.dart';

/// Abstraction over the background relay service.
///
/// The UI and view-model depend on this rather than the platform-coupled
/// `flutter_background_service`, which lets them be tested with a fake. The
/// real implementation is `RelayBackgroundService`.
abstract class RelayServiceController {
  /// Live connection status pushed from the background isolate.
  Stream<SocketStatus> get statusStream;

  /// SMS-send requests received in the background isolate.
  Stream<SmsRequest> get requestStream;

  /// Human-readable result of each background SMS send.
  Stream<String> get smsResultStream;

  Future<bool> isRunning();

  /// Starts the service (if needed) and asks it to re-emit current state.
  Future<void> start();

  /// Stops the service and suppresses auto-restart.
  void stop();

  /// Requests the runtime permissions the background work needs. Must run in
  /// the foreground.
  Future<void> ensurePermissions();
}
