class MailException implements Exception {
  const MailException(this.message);
  final String message;
  @override
  String toString() => message;
}
