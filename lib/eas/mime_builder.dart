import 'dart:convert';
import 'dart:typed_data';

/// Сборка MIME-сообщений для команды EAS SendMail.
class MimeBuilder {
  MimeBuilder._();

  /// MIME с HTML-телом (multipart/alternative: plain + html).
  static String buildHtml({
    required String from,
    required String to,
    required String subject,
    required String htmlBody,
    List<MimeAttachment>? attachments,
  }) {
    final plain = htmlBody
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final date = DateTime.now().toUtc();
    final dateHeader = _dateHeader(date);

    if (attachments == null || attachments.isEmpty) {
      final altBoundary = '----=_alt_${DateTime.now().millisecondsSinceEpoch}';
      return _joinHeaders([
        'From: $from',
        'To: $to',
        'Subject: $subject',
        'Date: $dateHeader',
        'MIME-Version: 1.0',
        'Content-Type: multipart/alternative; boundary="$altBoundary"',
        '',
        '--$altBoundary',
        'Content-Type: text/plain; charset="utf-8"',
        'Content-Transfer-Encoding: 8bit',
        '',
        plain,
        '--$altBoundary',
        'Content-Type: text/html; charset="utf-8"',
        'Content-Transfer-Encoding: 8bit',
        '',
        htmlBody,
        '--$altBoundary--',
      ]);
    }

    final mixedBoundary = '----=_mixed_${DateTime.now().millisecondsSinceEpoch}';
    final altBoundary = '----=_alt_${DateTime.now().millisecondsSinceEpoch}';
    final buffer = StringBuffer()
      ..writeln('From: $from')
      ..writeln('To: $to')
      ..writeln('Subject: $subject')
      ..writeln('Date: $dateHeader')
      ..writeln('MIME-Version: 1.0')
      ..writeln('Content-Type: multipart/mixed; boundary="$mixedBoundary"')
      ..writeln()
      ..writeln('--$mixedBoundary')
      ..writeln('Content-Type: multipart/alternative; boundary="$altBoundary"')
      ..writeln()
      ..writeln('--$altBoundary')
      ..writeln('Content-Type: text/plain; charset="utf-8"')
      ..writeln('Content-Transfer-Encoding: 8bit')
      ..writeln()
      ..writeln(plain)
      ..writeln('--$altBoundary')
      ..writeln('Content-Type: text/html; charset="utf-8"')
      ..writeln('Content-Transfer-Encoding: 8bit')
      ..writeln()
      ..writeln(htmlBody)
      ..writeln('--$altBoundary--');

    for (final att in attachments) {
      final b64 = base64Encode(att.bytes);
      buffer
        ..writeln('--$mixedBoundary')
        ..writeln('Content-Type: ${att.contentType}; name="${att.filename}"')
        ..writeln('Content-Transfer-Encoding: base64')
        ..writeln('Content-Disposition: attachment; filename="${att.filename}"')
        ..writeln()
        ..writeln(_wrapBase64(b64));
    }
    buffer.writeln('--$mixedBoundary--');
    return buffer.toString().replaceAll('\n', '\r\n');
  }

  static String build({
    required String from,
    required String to,
    required String subject,
    required String body,
    List<MimeAttachment>? attachments,
  }) {
    final dateHeader = _dateHeader(DateTime.now().toUtc());

    if (attachments == null || attachments.isEmpty) {
      return _joinHeaders([
        'From: $from',
        'To: $to',
        'Subject: $subject',
        'Date: $dateHeader',
        'MIME-Version: 1.0',
        'Content-Type: text/plain; charset="utf-8"',
        'Content-Transfer-Encoding: 8bit',
        '',
        body,
      ]);
    }

    final boundary = '----=_EASMail_${DateTime.now().millisecondsSinceEpoch}';
    final buffer = StringBuffer()
      ..writeln('From: $from')
      ..writeln('To: $to')
      ..writeln('Subject: $subject')
      ..writeln('Date: $dateHeader')
      ..writeln('MIME-Version: 1.0')
      ..writeln('Content-Type: multipart/mixed; boundary="$boundary"')
      ..writeln()
      ..writeln('--$boundary')
      ..writeln('Content-Type: text/plain; charset="utf-8"')
      ..writeln('Content-Transfer-Encoding: 8bit')
      ..writeln()
      ..writeln(body);

    for (final att in attachments) {
      final b64 = base64Encode(att.bytes);
      buffer
        ..writeln('--$boundary')
        ..writeln('Content-Type: ${att.contentType}; name="${att.filename}"')
        ..writeln('Content-Transfer-Encoding: base64')
        ..writeln('Content-Disposition: attachment; filename="${att.filename}"')
        ..writeln()
        ..writeln(_wrapBase64(b64));
    }

    buffer.writeln('--$boundary--');
    return buffer.toString().replaceAll('\n', '\r\n');
  }

  static String _dateHeader(DateTime date) {
    final utc = date.toUtc();
    return '${_weekday(utc.weekday)}, ${utc.day.toString().padLeft(2, '0')} '
        '${_month(utc.month)} ${utc.year} '
        '${utc.hour.toString().padLeft(2, '0')}:'
        '${utc.minute.toString().padLeft(2, '0')}:'
        '${utc.second.toString().padLeft(2, '0')} +0000';
  }

  static String _joinHeaders(List<String> lines) {
    return lines.join('\r\n');
  }

  static String _wrapBase64(String b64, {int lineLength = 76}) {
    final chunks = <String>[];
    for (var i = 0; i < b64.length; i += lineLength) {
      chunks.add(b64.substring(i, i + lineLength > b64.length ? b64.length : i + lineLength));
    }
    return chunks.join('\r\n');
  }

  static String _weekday(int w) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w - 1];

  static String _month(int m) => const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][m - 1];
}

class MimeAttachment {
  const MimeAttachment({
    required this.filename,
    required this.bytes,
    this.contentType = 'application/octet-stream',
  });

  final String filename;
  final Uint8List bytes;
  final String contentType;
}
