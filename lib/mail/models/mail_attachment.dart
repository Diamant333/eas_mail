class MailAttachment {
  const MailAttachment({
    required this.displayName,
    required this.fileReference,
    this.contentId,
    this.isInline = false,
    this.size,
  });

  final String displayName;
  /// EAS: FileReference. IMAP: `uid:<uid>:part:<index>`.
  final String fileReference;
  final String? contentId;
  final bool isInline;
  final int? size;
}
