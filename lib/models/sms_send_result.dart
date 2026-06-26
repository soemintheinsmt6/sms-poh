/// Outcome of an attempt to send an SMS through the SIM.
///
/// This is the domain-level result the rest of the app reasons about, so the
/// view and view-model never have to know about `permission_handler` or
/// `another_telephony` status types.
enum SmsSendResult {
  /// The message was handed to the SIM for sending.
  sent,

  /// The SEND_SMS permission was denied this time (can be asked again).
  permissionDenied,

  /// The SEND_SMS permission was permanently denied; only Settings can grant it.
  permissionPermanentlyDenied,
}
