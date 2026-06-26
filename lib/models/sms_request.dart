/// A single SMS-send request received over the socket.
///
/// Matches the server shape `{"phone_number": "...", "otp": "..."}`.
class SmsRequest {
  const SmsRequest({required this.phoneNumber, required this.code});

  final String phoneNumber;
  final String code;

  factory SmsRequest.fromJson(Map<String, dynamic> json) => SmsRequest(
    phoneNumber: json['phone_number']?.toString() ?? '',
    code: json['otp']?.toString() ?? '',
  );

  /// True when both fields are present — i.e. this really is a send request
  /// and not some other event on the channel.
  bool get isValid => phoneNumber.isNotEmpty && code.isNotEmpty;

  @override
  String toString() => 'SmsRequest(phoneNumber: $phoneNumber, code: $code)';
}
