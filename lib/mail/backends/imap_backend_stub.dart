import 'dart:typed_data';

import '../../eas/mime_builder.dart';
import '../../models/mail_folder.dart';
import '../mail_exception.dart';
import '../mail_backend.dart';
import '../models/mail_account.dart';
import '../models/mail_message.dart';

/// Заглушка для Web — IMAP через RawSocket недоступен.
class ImapMailBackend implements MailBackend {
  static const _msg =
      'IMAP/SMTP не поддерживается в браузере. Запустите: flutter run -d windows';

  @override
  Future<void> connect(MailAccount account, {bool useAutodiscover = true}) {
    throw const MailException(_msg);
  }

  @override
  Future<List<MailMessage>> fetchInbox({int limit = 0, int page = 1}) =>
      throw const MailException(_msg);

  @override
  Future<List<MailFolder>> fetchFolders() => throw const MailException(_msg);

  @override
  Future<List<MailMessage>> fetchFolder(String folderId,
          {int limit = 0, int page = 1}) =>
      throw const MailException(_msg);

  @override
  Future<MailMessage> loadMessageBody(MailMessage message) =>
      throw const MailException(_msg);

  @override
  Future<void> markAsRead(MailMessage message) async {}

  @override
  Future<void> deleteMessage(MailMessage message) async {}

  @override
  Future<void> sendMail({
    required MailAccount account,
    required String to,
    required String subject,
    required String body,
    List<MimeAttachment>? attachments,
    bool isHtml = false,
  }) =>
      throw const MailException(_msg);

  @override
  Future<Uint8List> loadAttachmentBytes({
    required MailMessage message,
    required int attachmentIndex,
  }) =>
      throw const MailException(_msg);

  @override
  Future<String> downloadAttachment({
    required MailMessage message,
    required int attachmentIndex,
  }) =>
      throw const MailException(_msg);

  @override
  Future<void> disconnect() async {}
}
