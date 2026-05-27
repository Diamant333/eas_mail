import 'mail_attachment.dart';

class MailMessage {
  const MailMessage({
    required this.serverId,
    required this.subject,
    required this.from,
    required this.collectionId,
    this.to,
    this.body,
    this.bodyHtml,
    this.read = false,
    this.dateReceived,
    this.attachments = const [],
    this.bodyLoaded = true,
  });

  final String serverId;
  final String collectionId;
  final String subject;
  final String from;
  final String? to;
  final String? body;
  final String? bodyHtml;
  final bool read;
  final DateTime? dateReceived;
  final List<MailAttachment> attachments;

  /// false = envelope-only fetch; body/attachments not yet loaded.
  final bool bodyLoaded;

  bool get hasAttachments => attachments.isNotEmpty;

  bool get hasHtmlBody => bodyHtml != null && bodyHtml!.trim().isNotEmpty;

  String get displayHtml {
    if (hasHtmlBody) return bodyHtml!;
    final text = body?.trim() ?? '';
    if (text.isEmpty) return '<p><i>(пустое письмо)</i></p>';
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return '<pre style="white-space:pre-wrap;font-family:inherit;">$escaped</pre>';
  }

  String get previewText {
    if (body != null && body!.trim().isNotEmpty) return body!.trim();
    if (hasHtmlBody) {
      return bodyHtml!
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    return '';
  }

  MailMessage copyWith({
    bool? read,
    String? body,
    String? bodyHtml,
    bool? bodyLoaded,
    List<MailAttachment>? attachments,
  }) =>
      MailMessage(
        serverId: serverId,
        collectionId: collectionId,
        subject: subject,
        from: from,
        to: to,
        body: body ?? this.body,
        bodyHtml: bodyHtml ?? this.bodyHtml,
        read: read ?? this.read,
        dateReceived: dateReceived,
        attachments: attachments ?? this.attachments,
        bodyLoaded: bodyLoaded ?? this.bodyLoaded,
      );
}
